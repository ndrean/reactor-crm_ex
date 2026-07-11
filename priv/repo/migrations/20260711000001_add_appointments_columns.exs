defmodule CrmReactor.Repo.Migrations.AddAppointmentsColumns do
  use Ecto.Migration

  def up do
    tenants =
      repo().query!("SELECT schema_name FROM global_registry.tenants")
      |> Map.get(:rows)
      |> List.flatten()

    for schema <- tenants do
      execute """
      ALTER TABLE #{schema}.todos
        ADD COLUMN IF NOT EXISTS starts_at TIMESTAMPTZ,
        ADD COLUMN IF NOT EXISTS ends_at TIMESTAMPTZ,
        ADD COLUMN IF NOT EXISTS location TEXT,
        ADD COLUMN IF NOT EXISTS reminder_minutes INTEGER DEFAULT 30,
        ADD COLUMN IF NOT EXISTS reminder_job_id BIGINT
      """
    end
  end

  def down do
    tenants =
      repo().query!("SELECT schema_name FROM global_registry.tenants")
      |> Map.get(:rows)
      |> List.flatten()

    for schema <- tenants do
      execute """
      ALTER TABLE #{schema}.todos
        DROP COLUMN IF EXISTS starts_at,
        DROP COLUMN IF EXISTS ends_at,
        DROP COLUMN IF EXISTS location,
        DROP COLUMN IF EXISTS reminder_minutes,
        DROP COLUMN IF EXISTS reminder_job_id
      """
    end
  end
end
