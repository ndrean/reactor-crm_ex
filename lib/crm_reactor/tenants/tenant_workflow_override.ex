defmodule CrmReactor.Tenants.TenantWorkflowOverride do
  use Ecto.Schema
  import Ecto.Changeset

  @schema_prefix "global_registry"
  @primary_key false

  schema "tenant_workflow_overrides" do
    field :tenant_id, :string
    field :workflow_name, :string
    field :enabled, :boolean, default: true
  end

  def changeset(override, attrs) do
    override
    |> cast(attrs, [:tenant_id, :workflow_name, :enabled])
    |> validate_required([:tenant_id, :workflow_name, :enabled])
  end
end
