defmodule Mix.Tasks.Crm.EmbedRegistry do
  @shortdoc "Populate hint_embedding for module_registry rows via Ollama"
  @moduledoc """
  Embeds `prompt_hint` text for all active `ModuleRegistry` rows using the Ollama
  mxbai-embed-large model and stores the result in the `hint_embedding` column.

  By default only processes rows where `hint_embedding IS NULL`.
  Pass `--force` to re-embed all active rows.

  ## Usage

      mix crm.embed_registry
      mix crm.embed_registry --force
  """
  use Mix.Task

  alias CrmReactor.{Repo, Tenants.ModuleRegistry}

  import Ecto.Query

  @requirements ["app.start"]

  @impl Mix.Task
  def run(args) do
    force = "--force" in args

    query =
      if force do
        from(r in ModuleRegistry, where: r.active == true)
      else
        from(r in ModuleRegistry, where: r.active == true and is_nil(r.hint_embedding))
      end

    rows = Repo.all(query)

    Mix.shell().info(
      "Found #{length(rows)} rows to embed#{if force, do: " (--force)", else: ""}."
    )

    Enum.each(rows, fn row ->
      text = row.prompt_hint || "#{row.workflow_name} #{row.action}"

      case embedder().embed(text) do
        {:ok, embedding} ->
          Repo.update_all(
            from(r in ModuleRegistry, where: r.id == ^row.id),
            set: [hint_embedding: embedding]
          )

          Mix.shell().info("  [ok] #{row.workflow_name}.#{row.action} (id=#{row.id})")

        {:error, reason} ->
          Mix.shell().error(
            "  [error] #{row.workflow_name}.#{row.action} (id=#{row.id}): #{inspect(reason)}"
          )
      end
    end)

    Mix.shell().info("Done.")
  end

  defp embedder do
    Application.get_env(:crm_reactor, :embedder, CrmReactor.AI.Embedder)
  end
end
