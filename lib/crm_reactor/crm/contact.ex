defmodule CrmReactor.CRM.Contact do
  use Ecto.Schema
  import Ecto.Changeset

  schema "contacts" do
    field :first_name, :string
    field :last_name, :string
    field :email, CrmReactor.Encrypted.Binary
    field :email_hash, CrmReactor.Encrypted.HMAC
    field :phone, CrmReactor.Encrypted.Binary
    field :phone_hash, CrmReactor.Encrypted.HMAC
    field :company_name, :string

    timestamps(type: :utc_datetime, inserted_at: :created_at, updated_at: false)
  end

  def changeset(contact, attrs) do
    contact
    |> cast(attrs, [:first_name, :last_name, :email, :phone, :company_name])
    |> validate_required([:first_name])
    |> put_hashes()
  end

  defp put_hashes(changeset) do
    changeset
    |> put_hash(:email, :email_hash)
    |> put_phone_hash()
  end

  defp put_hash(changeset, field, hash_field) do
    case get_change(changeset, field) do
      nil -> changeset
      value -> put_change(changeset, hash_field, value)
    end
  end

  defp put_phone_hash(changeset) do
    case get_change(changeset, :phone) do
      nil -> changeset
      value -> put_change(changeset, :phone_hash, normalize_phone(value))
    end
  end

  # Strip non-digits, keep last 9 digits — matches international vs local formats.
  # "06 12 13 14 15" → "612131415", "+33612131415" → "612131415"
  defp normalize_phone(phone) do
    phone
    |> String.replace(~r/\D/, "")
    |> String.slice(-9, 9)
  end
end
