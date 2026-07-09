defmodule CrmReactor.AI.ExampleSeeder do
  @moduledoc """
  Seeds and embeds workflow example phrases used for two-pass intent routing.

  Called from both `CrmReactor.Release.embed_examples/0` (production) and
  `Mix.Tasks.Crm.EmbedExamples` (development). The corpus is loaded from
  `priv/ai/seed_corpus.json` — edit that file to add or remove examples.
  """

  alias CrmReactor.Repo
  alias CrmReactor.Tenants.RegistryExample

  import Ecto.Query

  require Logger

  @doc "Returns the seed corpus as a list of `{workflow, phrase}` tuples."
  def seed_corpus do
    path = Application.app_dir(:crm_reactor, "priv/ai/seed_corpus.json")

    path
    |> File.read!()
    |> Jason.decode!()
    |> Enum.map(fn %{"workflow" => w, "phrase" => p} -> {w, p} end)
  end

  @doc """
  Upserts the seed corpus into `registry_examples` then embeds rows where
  `embedding IS NULL`. Pass `force: true` to re-embed all rows.

  Returns `{embedded, errors}` counts.
  """
  def seed_and_embed(opts \\ []) do
    force = Keyword.get(opts, :force, false)
    embedder = Keyword.get(opts, :embedder, CrmReactor.AI.Embedder)

    upsert_corpus()

    query =
      if force do
        from(e in RegistryExample)
      else
        from(e in RegistryExample, where: is_nil(e.embedding))
      end

    rows = Repo.all(query)
    embed_rows(rows, embedder)
  end

  defp upsert_corpus do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    Enum.each(seed_corpus(), fn {workflow, phrase} ->
      Repo.insert(
        %RegistryExample{workflow_name: workflow, phrase: phrase, inserted_at: now},
        on_conflict: :nothing,
        conflict_target: [:workflow_name, :phrase],
        prefix: "global_registry"
      )
    end)
  end

  defp embed_rows(rows, embedder) do
    Enum.reduce(rows, {0, 0}, fn row, {ok_count, err_count} ->
      case embedder.embed(row.phrase) do
        {:ok, embedding} ->
          Repo.update_all(
            from(e in RegistryExample, where: e.id == ^row.id),
            set: [embedding: embedding]
          )

          {ok_count + 1, err_count}

        {:error, reason} ->
          Logger.warning(
            "ExampleSeeder: failed to embed \"#{String.slice(row.phrase, 0, 40)}\": #{inspect(reason)}"
          )

          {ok_count, err_count + 1}
      end
    end)
  end
end
