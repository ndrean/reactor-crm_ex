defmodule CrmReactor.Repo.Migrations.AddWorkflowExpenses do
  use Ecto.Migration

  def up do
    execute """
    INSERT INTO global_registry.module_registry (workflow_name, action, params_schema, prompt_hint, active) VALUES
      ('expenses', 'submit',  '{"required":["amount"],"optional":["date","category","description","contact_name","currency"]}',
       'soumet une note de frais, un reçu, un ticket, une dépense ; montant obligatoire ; catégories : restaurant, transport, hébergement, fournitures, autre', true),
      ('expenses', 'list',    '{"optional":["category","date","period","contact_name","status"]}',
       'liste les notes de frais, dépenses ; filtre par catégorie, date, période ou statut', true),
      ('expenses', 'delete',  '{"required":["description"],"optional":["date","amount"]}',
       'supprime une note de frais ; description ou montant pour identifier', true)
    """
  end

  def down do
    execute "DELETE FROM global_registry.module_registry WHERE workflow_name = 'expenses'"
  end
end
