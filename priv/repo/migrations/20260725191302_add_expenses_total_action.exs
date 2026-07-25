defmodule CrmReactor.Repo.Migrations.AddExpensesTotalAction do
  use Ecto.Migration

  def up do
    execute """
    INSERT INTO global_registry.module_registry (workflow_name, action, params_schema, prompt_hint, active) VALUES
      ('expenses', 'total', '{"optional":["category","date","period","contact_name","status"]}',
       'calcule le total des notes de frais, somme des dépenses, combien j''ai dépensé, total par catégorie', true)
    """
  end

  def down do
    execute "DELETE FROM global_registry.module_registry WHERE workflow_name = 'expenses' AND action = 'total'"
  end
end
