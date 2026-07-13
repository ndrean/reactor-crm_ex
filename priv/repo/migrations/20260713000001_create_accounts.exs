defmodule CrmReactor.Repo.Migrations.CreateAccounts do
  use Ecto.Migration

  def change do
    execute "CREATE EXTENSION IF NOT EXISTS citext", "DROP EXTENSION IF EXISTS citext"

    create table(:accounts, prefix: "global_registry") do
      add :email, :citext, null: false
      add :name, :string
      add :hashed_password, :string
      add :role, :string, null: false, default: "user"
      add :tenant_id, :string
      add :confirmed_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create unique_index(:accounts, [:email], prefix: "global_registry")

    create table(:account_tokens, prefix: "global_registry") do
      add :account_id, references(:accounts, on_delete: :delete_all, prefix: "global_registry"),
        null: false

      add :token, :binary, null: false
      add :context, :string, null: false
      add :sent_to, :string

      timestamps(type: :utc_datetime, updated_at: false)
    end

    create index(:account_tokens, [:account_id], prefix: "global_registry")
    create unique_index(:account_tokens, [:context, :token], prefix: "global_registry")
  end
end
