defmodule CrmReactor.Repo.Migrations.CreateRoutingSignals do
  use Ecto.Migration

  def up do
    execute """
    CREATE TABLE global_registry.routing_signals (
      id               bigserial PRIMARY KEY,
      tenant_id        text NOT NULL,
      raw_input        text NOT NULL,
      cosine_workflow  text,
      cosine_score     float,
      pass1_workflow   text,
      pass1_confidence float,
      pass2_workflow   text,
      llm_confirmed    boolean NOT NULL DEFAULT false,
      user_corrected   boolean,
      inserted_at      timestamptz NOT NULL DEFAULT now()
    )
    """
  end

  def down do
    execute "DROP TABLE IF EXISTS global_registry.routing_signals"
  end
end
