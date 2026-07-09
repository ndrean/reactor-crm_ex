defmodule CrmReactor.Repo.Migrations.CreateRoutingThresholds do
  use Ecto.Migration

  def up do
    execute """
    CREATE TABLE global_registry.routing_thresholds (
      workflow_name  text PRIMARY KEY,
      threshold      float NOT NULL DEFAULT 0.70,
      sample_count   integer NOT NULL DEFAULT 0,
      calibrated_at  timestamptz NOT NULL DEFAULT now()
    )
    """

    execute """
    INSERT INTO global_registry.routing_thresholds (workflow_name, threshold, sample_count)
    VALUES
      ('contacts', 0.70, 0),
      ('todos',    0.70, 0),
      ('data',     0.70, 0),
      ('help',     0.70, 0)
    """
  end

  def down do
    execute "DROP TABLE IF EXISTS global_registry.routing_thresholds"
  end
end
