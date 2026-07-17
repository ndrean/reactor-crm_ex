defmodule CrmReactor.Tenants.UserMapping do
  use Ecto.Schema
  import Ecto.Changeset

  @schema_prefix "global_registry"

  schema "user_mappings" do
    field :email, :string
    field :tenant_id, :string
    field :telegram_id, :string
  end

  def changeset(mapping, attrs) do
    mapping
    |> cast(attrs, [:email, :tenant_id, :telegram_id])
    |> validate_required([:email, :tenant_id])
    |> validate_format(:email, ~r/@/)
    |> unique_constraint(:email)
    |> unique_constraint(:telegram_id)
  end
end
