defmodule CrmReactor.Repo.Migrations.AddWorkflowContacts do
  use Ecto.Migration

  def up do
    execute """
    INSERT INTO global_registry.module_registry (workflow_name, action, params_schema, prompt_hint, active) VALUES
      ('contacts', 'search',  '{"required":["search_name"]}',                                                                      'cherche, trouve, affiche contact',    true),
      ('contacts', 'count',   '{"optional":["filter"]}',                                                                           'combien de contacts',                 true),
      ('contacts', 'create',  '{"required":["first_name"],"optional":["last_name","email","phone","company_name"]}',                'crée, ajoute un contact',             true),
      ('contacts', 'update',  '{"required":["search_name"],"optional":["first_name","last_name","email","phone","company_name"]}',  'modifie, change un contact',          true),
      ('contacts', 'delete',  '{"required":["search_name"]}',                                                                      'supprime un contact',                 true)
    """
  end

  def down do
    execute "DELETE FROM global_registry.module_registry WHERE workflow_name = 'contacts'"
  end
end
