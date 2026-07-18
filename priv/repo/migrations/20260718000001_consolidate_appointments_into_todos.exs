defmodule CrmReactor.Repo.Migrations.ConsolidateAppointmentsIntoTodos do
  use Ecto.Migration

  @moduledoc """
  Merges the 'appointments' workflow into 'todos' in module_registry.
  Actions are renamed: create → create_appointment, list → list_appointments,
  cancel → cancel_appointment, reschedule stays reschedule.
  """

  def up do
    # Rename actions and move to todos workflow
    execute """
    UPDATE global_registry.module_registry
    SET workflow_name = 'todos',
        action = CASE action
          WHEN 'create' THEN 'create_appointment'
          WHEN 'list'   THEN 'list_appointments'
          WHEN 'cancel' THEN 'cancel_appointment'
          ELSE action
        END
    WHERE workflow_name = 'appointments'
    """

    # Migrate any tenant subscription overrides
    execute """
    UPDATE global_registry.tenant_workflow_overrides
    SET workflow_name = 'todos'
    WHERE workflow_name = 'appointments'
      AND NOT EXISTS (
        SELECT 1 FROM global_registry.tenant_workflow_overrides t2
        WHERE t2.tenant_id = tenant_workflow_overrides.tenant_id
          AND t2.workflow_name = 'todos'
      )
    """

    # Delete orphaned overrides (tenant already has a 'todos' override)
    execute """
    DELETE FROM global_registry.tenant_workflow_overrides
    WHERE workflow_name = 'appointments'
    """
  end

  def down do
    # Restore appointments workflow rows
    execute """
    UPDATE global_registry.module_registry
    SET workflow_name = 'appointments',
        action = CASE action
          WHEN 'create_appointment' THEN 'create'
          WHEN 'list_appointments'  THEN 'list'
          WHEN 'cancel_appointment' THEN 'cancel'
          ELSE action
        END
    WHERE workflow_name = 'todos'
      AND action IN ('create_appointment', 'list_appointments', 'cancel_appointment', 'reschedule')
    """
  end
end
