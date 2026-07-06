defmodule CrmReactor.Tenants.UserMapping do
  use Ecto.Schema
  import Ecto.Changeset

  @schema_prefix "global_registry"

  schema "user_mappings" do
    field :user_identifier, :string
    field :tenant_id, :string
    field :user_email, :string
  end

  def changeset(mapping, attrs) do
    mapping
    |> cast(attrs, [:user_identifier, :tenant_id, :user_email])
    |> validate_required([:user_identifier, :tenant_id])
    |> unique_constraint(:user_identifier)
  end
end
