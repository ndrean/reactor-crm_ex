defmodule Mix.Tasks.Crm.EmbedExamples do
  @shortdoc "Seed and embed workflow example phrases for semantic routing"
  @moduledoc """
  Upserts example phrases from the built-in seed corpus into `registry_examples`,
  then embeds all rows where `embedding IS NULL` using Ollama mxbai-embed-large.

  By default only processes rows where `embedding IS NULL`.
  Pass `--force` to re-embed all rows.

  ## Usage

      mix crm.embed_examples
      mix crm.embed_examples --force
  """
  use Mix.Task

  alias CrmReactor.AI.{ExamplesCache, ExampleSeeder}

  @requirements ["app.start"]

  @impl Mix.Task
  def run(args) do
    force = "--force" in args
    corpus_size = length(ExampleSeeder.seed_corpus())

    Mix.shell().info("Seeding #{corpus_size} example phrases...")

    {embedded, errors} =
      ExampleSeeder.seed_and_embed(
        force: force,
        embedder: Application.get_env(:crm_reactor, :embedder, CrmReactor.AI.Embedder)
      )

    Mix.shell().info("Embedded: #{embedded}, errors: #{errors}")
    ExamplesCache.reload()
    Mix.shell().info("Done. ExamplesCache reloaded.")
  end
end
