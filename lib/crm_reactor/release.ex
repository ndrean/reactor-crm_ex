defmodule CrmReactor.Release do
  @moduledoc "Release tasks for running migrations outside Mix."
  @app :crm_reactor

  def migrate do
    load_app()

    for repo <- repos() do
      {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :up, all: true))
    end
  end

  @doc """
  Seeds and embeds workflow example phrases for two-pass intent routing.

  Run after `migrate/0` from the container entrypoint, before starting the app.
  Requires Ollama to be reachable at the configured `OLLAMA_URL`.
  Idempotent: only embeds rows where `embedding IS NULL`.

  ## Container entrypoint

      ./app eval "CrmReactor.Release.migrate()"
      ./app eval "CrmReactor.Release.embed_examples()"
      ./app start
  """
  def embed_examples do
    # Start the full app so Finch (HTTP) and Repo are both available.
    # This is safe in a release eval: the process tree is torn down when eval exits.
    {:ok, _} = Application.ensure_all_started(@app)

    {embedded, errors} = CrmReactor.AI.ExampleSeeder.seed_and_embed()
    IO.puts("embed_examples: #{embedded} embedded, #{errors} errors")
  end

  def rollback(repo, version) do
    load_app()
    {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :down, to: version))
  end

  defp repos do
    Application.fetch_env!(@app, :ecto_repos)
  end

  defp load_app do
    Application.ensure_all_started(:ssl)
    Application.load(@app)
  end
end
