defmodule CrmReactor.Repo.Migrations.AddWorkflowHelp do
  use Ecto.Migration

  def up do
    execute """
    INSERT INTO global_registry.module_registry (workflow_name, action, params_schema, prompt_hint, active) VALUES
      ('help', 'help', '{"required":[],"optional":[]}', 'aide et fonctionnement du systeme', true)
    """
  end

  def down do
    execute "DELETE FROM global_registry.module_registry WHERE workflow_name = 'help'"
  end
end
