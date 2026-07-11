defmodule CrmReactor.Repo.Migrations.AddWorkflowAppointments do
  use Ecto.Migration

  def up do
    execute """
    INSERT INTO global_registry.module_registry (workflow_name, action, params_schema, prompt_hint, active) VALUES
      ('appointments', 'create',     '{"required":["subject","date","time"],"optional":["duration","location","contact_name","reminder_minutes"]}',
       'planifie un rendez-vous, réunion, créneau ; date et heure obligatoires', true),
      ('appointments', 'list',       '{"optional":["date","contact_name","period"]}',
       'liste les rendez-vous, prochains rdv ; filtre par date ou contact', true),
      ('appointments', 'cancel',     '{"required":["subject"],"optional":["date","contact_name"]}',
       'annule un rendez-vous ou une réunion', true),
      ('appointments', 'reschedule', '{"required":["subject"],"optional":["new_date","new_time","contact_name"]}',
       'déplace, reporte, reprogramme un rendez-vous', true)
    """
  end

  def down do
    execute "DELETE FROM global_registry.module_registry WHERE workflow_name = 'appointments'"
  end
end
