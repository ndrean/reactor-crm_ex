defmodule CrmReactor.Repo.Migrations.CreateRegistryExamples do
  use Ecto.Migration

  def up do
    execute """
    CREATE TABLE global_registry.registry_examples (
      id          bigserial PRIMARY KEY,
      workflow_name text NOT NULL,
      phrase       text NOT NULL,
      embedding    float8[],
      inserted_at  timestamptz NOT NULL DEFAULT now(),
      UNIQUE(workflow_name, phrase)
    )
    """
  end

  def down do
    execute "DROP TABLE IF EXISTS global_registry.registry_examples"
  end
end
