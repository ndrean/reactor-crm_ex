defmodule CrmReactor.AI.RoutingSignal do
  @moduledoc "Persisted signal recording how each request was routed through the two-pass classifier."
  use Ecto.Schema

  @schema_prefix "global_registry"
  @primary_key {:id, :id, autogenerate: true}
  @timestamps_opts [type: :utc_datetime, updated_at: false]

  schema "routing_signals" do
    field :tenant_id, :string
    field :raw_input, :string
    field :cosine_workflow, :string
    field :cosine_score, :float
    field :pass1_workflow, :string
    field :pass1_confidence, :float
    field :pass2_workflow, :string
    field :llm_confirmed, :boolean, default: false
    field :user_corrected, :boolean
    field :reviewed, :boolean, default: false
    timestamps()
  end

  def changeset(signal, attrs) do
    import Ecto.Changeset

    signal
    |> cast(attrs, [
      :tenant_id,
      :raw_input,
      :cosine_workflow,
      :cosine_score,
      :pass1_workflow,
      :pass1_confidence,
      :pass2_workflow,
      :llm_confirmed,
      :user_corrected,
      :reviewed
    ])
    |> validate_required([:tenant_id, :raw_input])
  end
end
