defmodule CrmReactor.Repo.Migrations.AddWorkflowTodos do
  use Ecto.Migration

  def up do
    execute """
    INSERT INTO global_registry.module_registry (workflow_name, action, params_schema, prompt_hint, active) VALUES
      ('todos', 'list',     '{"optional":["due_before","due_after","due_on","contact_name"]}',                            'liste les tâches ; filtre par contact_name (prénom/nom), due_before/due_after/due_on pour les dates', true),
      ('todos', 'create',   '{"required":["subject"],"optional":["due_date","contact_name"]}',                            'crée une tâche ; contact_name pour la lier à un contact',                                            true),
      ('todos', 'complete', '{"required":["subject"],"optional":["contact_name"]}',                                       'termine/complète une tâche ; contact_name pour lever une ambiguïté',                                 true),
      ('todos', 'update',   '{"required":["subject"],"optional":["new_subject","due_date","start_date","contact_name"]}', 'modifie une tâche ; contact_name pour lever une ambiguïté',                                          true),
      ('todos', 'delete',   '{"required":["subject"],"optional":["contact_name"]}',                                       'supprime une tâche ; contact_name pour lever une ambiguïté',                                         true)
    """
  end

  def down do
    execute "DELETE FROM global_registry.module_registry WHERE workflow_name = 'todos'"
  end
end
