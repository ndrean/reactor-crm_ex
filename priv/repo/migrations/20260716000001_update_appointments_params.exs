defmodule CrmReactor.Repo.Migrations.UpdateAppointmentsParams do
  use Ecto.Migration

  def up do
    execute """
    UPDATE global_registry.module_registry
    SET params_schema = '{"optional":["due_on","due_before","due_after","contact_name"]}',
        prompt_hint = 'liste les rendez-vous, prochains rdv ; filtre par contact_name, due_on/due_before/due_after pour les dates'
    WHERE workflow_name = 'appointments' AND action = 'list'
    """
  end

  def down do
    execute """
    UPDATE global_registry.module_registry
    SET params_schema = '{"optional":["date","contact_name","period"]}',
        prompt_hint = 'liste les rendez-vous, prochains rdv ; filtre par date ou contact'
    WHERE workflow_name = 'appointments' AND action = 'list'
    """
  end
end
