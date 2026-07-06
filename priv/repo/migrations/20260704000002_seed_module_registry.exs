defmodule CrmReactor.Repo.Migrations.SeedModuleRegistry do
  use Ecto.Migration

  def up do
    execute """
    INSERT INTO global_registry.module_registry (workflow_name, action, params_schema, prompt_hint, active) VALUES
      ('contacts', 'search',  '{"required":["search_name"]}',                                                                      'cherche, trouve, affiche contact',                                                              true),
      ('contacts', 'count',   '{"optional":["filter"]}',                                                                           'combien de contacts',                                                                           true),
      ('contacts', 'create',  '{"required":["first_name"],"optional":["last_name","email","phone","company_name"]}',                'crée, ajoute un contact',                                                                       true),
      ('contacts', 'update',  '{"required":["search_name"],"optional":["first_name","last_name","email","phone","company_name"]}',  'modifie, change un contact',                                                                    true),
      ('contacts', 'delete',  '{"required":["search_name"]}',                                                                      'supprime un contact',                                                                           true),
      ('todos',    'list',    '{"optional":["due_before","due_after","due_on","contact_name"]}',                                    'liste les tâches ; filtre par contact_name (prénom/nom), due_before/due_after/due_on pour les dates', true),
      ('todos',    'create',  '{"required":["subject"],"optional":["due_date","contact_name"]}',                                   'crée une tâche ; contact_name pour la lier à un contact',                                       true),
      ('todos',    'complete','{"required":["subject"],"optional":["contact_name"]}',                                              'termine/complète une tâche ; contact_name pour lever une ambiguïté',                            true),
      ('todos',    'update',  '{"required":["subject"],"optional":["new_subject","due_date","start_date","contact_name"]}',         'modifie une tâche ; contact_name pour lever une ambiguïté',                                     true),
      ('todos',    'delete',  '{"required":["subject"],"optional":["contact_name"]}',                                              'supprime une tâche ; contact_name pour lever une ambiguïté',                                    true),
      ('data',     'dump',    '{}',                                                                                                 'exporte, rapport utilisation',                                                                  true)
    """
  end

  def down do
    execute "DELETE FROM global_registry.module_registry"
  end
end
