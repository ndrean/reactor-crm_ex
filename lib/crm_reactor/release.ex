defmodule CrmReactor.Release do
  @moduledoc "Release tasks for running migrations outside Mix."
  @app :crm_reactor

  def migrate do
    load_app()

    for repo <- repos() do
      {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :up, all: true))
    end
  end

  def create_admin do
    load_app()

    {:ok, _, _} =
      Ecto.Migrator.with_repo(CrmReactor.Repo, fn _repo ->
        email = System.get_env("ADMIN_EMAIL", "admin@example.com")
        password = System.get_env("ADMIN_PASSWORD")

        unless password do
          IO.puts("ADMIN_PASSWORD env var is required")
          System.halt(1)
        end

        do_create_admin(email, password)
      end)
  end

  def rollback(repo, version) do
    load_app()
    {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :down, to: version))
  end

  defp do_create_admin(email, password) do
    case CrmReactor.Repo.get_by(CrmReactor.Accounts.Account, email: email) do
      nil ->
        case CrmReactor.Accounts.create_admin_account(%{email: email, password: password}) do
          {:ok, account} -> IO.puts("Admin account created: #{account.email}")
          {:error, cs} -> IO.puts("Failed: #{inspect(cs.errors)}")
        end

      _existing ->
        IO.puts("Admin account #{email} already exists, skipping")
    end
  end

  defp repos do
    Application.fetch_env!(@app, :ecto_repos)
  end

  defp load_app do
    Application.ensure_all_started(:ssl)
    Application.load(@app)
  end
end
