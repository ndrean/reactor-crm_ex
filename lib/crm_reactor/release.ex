defmodule CrmReactor.Release do
  @moduledoc "Release tasks for running migrations outside Mix."
  @app :crm_reactor

  alias CrmReactor.Accounts.{Account, AccountToken}
  alias CrmReactor.Repo

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

  def list_admins do
    load_app()
    {:ok, _, _} = Ecto.Migrator.with_repo(Repo, fn _repo -> do_list_admins() end)
  end

  def delete_admin(email) do
    load_app()
    {:ok, _, _} = Ecto.Migrator.with_repo(Repo, fn _repo -> do_delete_admin(email) end)
  end

  def reset_password(email, new_password) do
    load_app()

    {:ok, _, _} =
      Ecto.Migrator.with_repo(Repo, fn _repo -> do_reset_password(email, new_password) end)
  end

  def rollback(repo, version) do
    load_app()
    {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :down, to: version))
  end

  defp do_list_admins do
    import Ecto.Query

    admins =
      from(a in Account, where: a.role == "admin", order_by: [asc: a.inserted_at])
      |> Repo.all()

    if Enum.empty?(admins) do
      IO.puts("No admin accounts found.")
    else
      IO.puts("Admin accounts:")
      for admin <- admins, do: IO.puts("  #{admin.email}  (created: #{admin.inserted_at})")
      IO.puts("\nTotal: #{length(admins)}")
    end
  end

  defp do_delete_admin(email) do
    import Ecto.Query

    admin_count = Repo.aggregate(from(a in Account, where: a.role == "admin"), :count)

    case Repo.get_by(Account, email: email, role: "admin") do
      nil ->
        IO.puts("No admin account found with email: #{email}")

      _account when admin_count <= 1 ->
        IO.puts("Cannot delete the last admin account.")

      account ->
        from(t in AccountToken, where: t.account_id == ^account.id) |> Repo.delete_all()
        Repo.delete!(account)
        IO.puts("Deleted admin account: #{email}")
    end
  end

  defp do_reset_password(email, new_password) do
    import Ecto.Query

    case Repo.get_by(Account, email: email) do
      nil ->
        IO.puts("No account found with email: #{email}")

      account ->
        case Account.password_changeset(account, %{password: new_password}) |> Repo.update() do
          {:ok, _} ->
            from(t in AccountToken,
              where: t.account_id == ^account.id and t.context == "session"
            )
            |> Repo.delete_all()

            IO.puts("Password reset for: #{email}")

          {:error, changeset} ->
            IO.puts("Failed: #{inspect(changeset.errors)}")
        end
    end
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
