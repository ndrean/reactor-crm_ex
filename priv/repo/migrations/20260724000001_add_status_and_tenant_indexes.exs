defmodule CrmReactor.Repo.Migrations.AddStatusAndTenantIndexes do
  use Ecto.Migration

  def up do
    # Index on user_mappings.tenant_id for admin tenant filtering
    create index(:user_mappings, [:tenant_id], prefix: "global_registry")

    # Index on execution_logs.status for each tenant schema
    for schema <- tenant_schemas() do
      execute """
      CREATE INDEX IF NOT EXISTS idx_execution_logs_status
        ON #{schema}.execution_logs (status)
      """
    end
  end

  def down do
    drop_if_exists index(:user_mappings, [:tenant_id], prefix: "global_registry")

    for schema <- tenant_schemas() do
      execute "DROP INDEX IF EXISTS #{schema}.idx_execution_logs_status"
    end
  end

  defp tenant_schemas do
    %{rows: rows} = repo().query!("SELECT schema_name FROM global_registry.tenants")
    Enum.map(rows, &List.first/1)
  end
end
