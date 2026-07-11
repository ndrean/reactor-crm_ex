defmodule CrmReactor.Repo.Migrations.AddWorkflowData do
  use Ecto.Migration

  def up do
    execute """
    INSERT INTO global_registry.module_registry (workflow_name, action, params_schema, prompt_hint, active) VALUES
      ('data', 'dump', '{}', 'exporte, rapport utilisation', true)
    """
  end

  def down do
    execute "DELETE FROM global_registry.module_registry WHERE workflow_name = 'data'"
  end
end
