defmodule CrmReactor.Repo.Migrations.AddTenantWorkflowOverrides do
  use Ecto.Migration

  def up do
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
    execute "DROP TABLE IF EXISTS global_registry.tenant_workflow_overrides"
  end
end
