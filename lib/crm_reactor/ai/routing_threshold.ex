defmodule CrmReactor.AI.RoutingThreshold do
  @moduledoc "Per-workflow confidence threshold for Pass 1 routing scoping."
  use Ecto.Schema

  @schema_prefix "global_registry"
  @primary_key {:workflow_name, :string, autogenerate: false}
  @timestamps_opts false

  schema "routing_thresholds" do
    field :threshold, :float
    field :sample_count, :integer
    field :calibrated_at, :utc_datetime
  end

  def changeset(threshold, attrs) do
    import Ecto.Changeset

    threshold
    |> cast(attrs, [:workflow_name, :threshold, :sample_count, :calibrated_at])
    |> validate_required([:workflow_name, :threshold])
  end
end
