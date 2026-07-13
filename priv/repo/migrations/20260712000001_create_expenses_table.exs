defmodule CrmReactor.Repo.Migrations.CreateExpensesTable do
  use Ecto.Migration

  def up do
    tenants =
      repo().query!("SELECT schema_name FROM global_registry.tenants")
      |> Map.get(:rows)
      |> List.flatten()

    for schema <- tenants do
      execute """
      CREATE TABLE IF NOT EXISTS #{schema}.expenses (
        id BIGSERIAL PRIMARY KEY,
        amount DECIMAL(10,2) NOT NULL,
        currency TEXT DEFAULT 'EUR',
        expense_date DATE NOT NULL,
        category TEXT,
        description TEXT,
        created_by TEXT NOT NULL,
        contact_id BIGINT REFERENCES #{schema}.contacts(id) ON DELETE SET NULL,
        status TEXT DEFAULT 'pending',
        attachment_key TEXT,
        created_at TIMESTAMPTZ DEFAULT NOW()
      )
      """
    end
  end

  def down do
    tenants =
      repo().query!("SELECT schema_name FROM global_registry.tenants")
      |> Map.get(:rows)
      |> List.flatten()

    for schema <- tenants do
      execute "DROP TABLE IF EXISTS #{schema}.expenses"
    end
  end
end
