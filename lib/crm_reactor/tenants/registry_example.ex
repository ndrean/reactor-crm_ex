defmodule CrmReactor.Tenants.RegistryExample do
  @moduledoc "Example phrase per workflow for embedding-based semantic routing."
  use Ecto.Schema

  @schema_prefix "global_registry"
  @primary_key {:id, :id, autogenerate: true}
  @timestamps_opts [type: :utc_datetime, updated_at: false]

  schema "registry_examples" do
    field :workflow_name, :string
    field :phrase, :string
    field :embedding, {:array, :float}
    timestamps()
  end

  def changeset(example, attrs) do
    import Ecto.Changeset

    example
    |> cast(attrs, [:workflow_name, :phrase, :embedding])
    |> validate_required([:workflow_name, :phrase])
  end
end
