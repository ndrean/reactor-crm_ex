defmodule Mix.Tasks.Crm.CreateAdmin do
  @moduledoc "Creates an admin account: mix crm.create_admin admin@example.com MyPassword"
  use Mix.Task

  @shortdoc "Create an admin account"

  @impl Mix.Task
  def run([email, password]) do
    Mix.Task.run("app.start")

    case CrmReactor.Accounts.create_admin_account(%{email: email, password: password}) do
      {:ok, account} ->
        Mix.shell().info("Admin account created: #{account.email} (id: #{account.id})")

      {:error, changeset} ->
        errors =
          Ecto.Changeset.traverse_errors(changeset, fn {msg, _} -> msg end)
          |> inspect()

        Mix.shell().error("Failed to create admin: #{errors}")
    end
  end

  def run(_) do
    Mix.shell().error("Usage: mix crm.create_admin EMAIL PASSWORD")
  end
end
