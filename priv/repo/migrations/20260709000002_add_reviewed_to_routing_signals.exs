defmodule CrmReactor.Repo.Migrations.AddReviewedToRoutingSignals do
  use Ecto.Migration

  def change do
    alter table(:routing_signals, prefix: "global_registry") do
      add :reviewed, :boolean, default: false, null: false
    end
  end
end
