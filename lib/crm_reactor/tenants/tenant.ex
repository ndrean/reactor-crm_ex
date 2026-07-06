defmodule CrmReactor.Tenants.Tenant do
  use Ecto.Schema
  import Ecto.Changeset

  @schema_prefix "global_registry"

  schema "tenants" do
    field :tenant_id, :string
    field :company_name, :string
    field :schema_name, :string
    field :admin_email, :string
    field :is_active, :boolean, default: true

    timestamps(type: :utc_datetime, updated_at: false)
  end

  def changeset(tenant, attrs) do
    tenant
    |> cast(attrs, [:tenant_id, :company_name, :admin_email])
    |> validate_required([:tenant_id, :company_name])
    |> unique_constraint(:tenant_id)
    |> put_schema_name()
  end

  defp put_schema_name(changeset) do
    case get_change(changeset, :tenant_id) do
      nil -> changeset
      tid -> put_change(changeset, :schema_name, "customer_#{tid}")
    end
  end
end
