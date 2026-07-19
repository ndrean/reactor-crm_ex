defmodule CrmReactor.Tenants.UserMapping do
  use Ecto.Schema
  import Ecto.Changeset

  @schema_prefix "global_registry"

  @statuses ~w(pending active suspended)

  schema "user_mappings" do
    field :email, :string
    field :tenant_id, :string
    field :telegram_id, :string
    field :status, :string, default: "active"
  end

  def changeset(mapping, attrs) do
    mapping
    |> cast(attrs, [:email, :tenant_id, :telegram_id, :status])
    |> validate_required([:email, :tenant_id])
    |> validate_format(:email, ~r/@/)
    |> validate_inclusion(:status, @statuses)
    |> unique_constraint(:email)
    |> unique_constraint(:telegram_id)
  end
end
