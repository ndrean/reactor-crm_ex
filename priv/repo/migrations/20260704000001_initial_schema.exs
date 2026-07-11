defmodule CrmReactor.Repo.Migrations.InitialSchema do
  use Ecto.Migration

  def up do
    # Oban job queue tables
    Oban.Migrations.up()

    # ── Global registry schema ─────────────────────────────────────────────

    execute "CREATE SCHEMA IF NOT EXISTS global_registry"

    create table(:tenants, prefix: "global_registry") do
      add :tenant_id, :string, null: false
      add :company_name, :string, null: false
      add :schema_name, :string, null: false
      add :is_active, :boolean, default: true
      add :admin_email, :string
      add :webhook_url, :text
      add :webhook_secret, :text

      timestamps(type: :utc_datetime, updated_at: false)
    end

    create unique_index(:tenants, [:tenant_id], prefix: "global_registry")

    create table(:user_mappings, prefix: "global_registry") do
      add :user_identifier, :string, null: false
      add :tenant_id, :string, null: false
      add :user_email, :string
    end

    create unique_index(:user_mappings, [:user_identifier], prefix: "global_registry")

    create table(:module_registry, prefix: "global_registry") do
      add :workflow_name, :string, null: false
      add :action, :string, null: false
      add :workflow_id, :string
      add :params_schema, :map
      add :prompt_hint, :string
      add :active, :boolean, default: true
    end

    create unique_index(:module_registry, [:workflow_name, :action], prefix: "global_registry")

    execute """
    CREATE TABLE global_registry.tenant_workflow_overrides (
      tenant_id     TEXT    NOT NULL,
      workflow_name TEXT    NOT NULL,
      enabled       BOOLEAN NOT NULL DEFAULT TRUE,
      PRIMARY KEY (tenant_id, workflow_name)
    )
    """
  end

  def down do
    execute "DROP SCHEMA IF EXISTS global_registry CASCADE"
    Oban.Migrations.down()
  end
end
