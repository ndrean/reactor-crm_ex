defmodule CrmReactor.Accounts.Account do
  use Ecto.Schema
  import Ecto.Changeset

  @schema_prefix "global_registry"

  schema "accounts" do
    field :email, :string
    field :name, :string
    field :password, :string, virtual: true, redact: true
    field :hashed_password, :string, redact: true
    field :role, :string, default: "user"
    field :tenant_id, :string
    field :confirmed_at, :utc_datetime
    field :suspended_at, :utc_datetime

    timestamps(type: :utc_datetime)
  end

  def registration_changeset(account, attrs) do
    account
    |> cast(attrs, [:email, :name, :password, :role, :tenant_id])
    |> validate_email()
    |> validate_password()
  end

  def invite_changeset(account, attrs) do
    account
    |> cast(attrs, [:email, :name, :role, :tenant_id])
    |> validate_email()
    |> validate_required([:tenant_id])
  end

  def password_changeset(account, attrs) do
    account
    |> cast(attrs, [:password])
    |> validate_password()
    |> put_confirm()
  end

  def valid_password?(%__MODULE__{hashed_password: hashed}, password)
      when is_binary(hashed) and byte_size(password) > 0 do
    Bcrypt.verify_pass(password, hashed)
  end

  def valid_password?(_, _) do
    Bcrypt.no_user_verify()
    false
  end

  defp validate_email(changeset) do
    changeset
    |> validate_required([:email])
    |> validate_format(:email, ~r/^[^\s]+@[^\s]+$/, message: "must have the @ sign and no spaces")
    |> validate_length(:email, max: 160)
    |> unsafe_validate_unique(:email, CrmReactor.Repo, prefix: "global_registry")
    |> unique_constraint(:email)
  end

  defp validate_password(changeset) do
    changeset
    |> validate_required([:password])
    |> validate_length(:password, min: 8, max: 72)
    |> hash_password()
  end

  defp hash_password(changeset) do
    case get_change(changeset, :password) do
      nil -> changeset
      password -> put_change(changeset, :hashed_password, Bcrypt.hash_pwd_salt(password))
    end
  end

  defp put_confirm(changeset) do
    if changeset.valid? do
      put_change(changeset, :confirmed_at, DateTime.utc_now() |> DateTime.truncate(:second))
    else
      changeset
    end
  end
end
