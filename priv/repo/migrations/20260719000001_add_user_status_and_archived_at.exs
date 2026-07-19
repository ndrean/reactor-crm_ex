defmodule CrmReactor.Repo.Migrations.AddUserStatusAndArchivedAt do
  use Ecto.Migration

  def up do
    # Add status to user_mappings
    execute """
    ALTER TABLE global_registry.user_mappings
    ADD COLUMN IF NOT EXISTS status TEXT NOT NULL DEFAULT 'active'
    """

    # Backfill: pending for accounts without confirmed_at, suspended for suspended accounts
    execute """
    UPDATE global_registry.user_mappings m
    SET status = CASE
      WHEN EXISTS (
        SELECT 1 FROM global_registry.accounts a
        WHERE a.email = m.email AND a.tenant_id = m.tenant_id
          AND a.suspended_at IS NOT NULL
      ) THEN 'suspended'
      WHEN EXISTS (
        SELECT 1 FROM global_registry.accounts a
        WHERE a.email = m.email AND a.tenant_id = m.tenant_id
          AND a.confirmed_at IS NULL
      ) THEN 'pending'
      ELSE 'active'
    END
    """

    # Add archived_at to todos and expenses in all tenant schemas
    tenants =
      repo().query!("SELECT schema_name FROM global_registry.tenants")
      |> Map.get(:rows)
      |> List.flatten()

    for schema <- tenants do
      execute """
      ALTER TABLE #{schema}.todos
      ADD COLUMN IF NOT EXISTS archived_at TIMESTAMPTZ
      """

      execute """
      ALTER TABLE #{schema}.expenses
      ADD COLUMN IF NOT EXISTS archived_at TIMESTAMPTZ
      """
    end
  end

  def down do
    execute "ALTER TABLE global_registry.user_mappings DROP COLUMN IF EXISTS status"

    tenants =
      repo().query!("SELECT schema_name FROM global_registry.tenants")
      |> Map.get(:rows)
      |> List.flatten()

    for schema <- tenants do
      execute "ALTER TABLE #{schema}.todos DROP COLUMN IF EXISTS archived_at"
      execute "ALTER TABLE #{schema}.expenses DROP COLUMN IF EXISTS archived_at"
    end
  end
end
