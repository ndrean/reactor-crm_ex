defmodule CrmReactor.Emails.IncomingEmail do
  use Ecto.Schema
  import Ecto.Changeset

  @schema_prefix "global_registry"
  @max_body_bytes 10_240

  schema "incoming_emails" do
    field :from_address, :string
    field :subject, :string
    field :body_text, :string
    field :status, :string, default: "pending"
    field :received_at, :utc_datetime
    field :attachments, {:array, :map}, default: []

    timestamps(type: :utc_datetime)
  end

  def changeset(email, attrs) do
    email
    |> cast(attrs, [:from_address, :subject, :body_text, :status, :received_at, :attachments])
    |> validate_required([:from_address, :received_at])
    |> validate_inclusion(:status, ["pending", "completed"])
    |> truncate_body_text()
  end

  defp truncate_body_text(changeset) do
    case get_change(changeset, :body_text) do
      nil ->
        changeset

      text when byte_size(text) > @max_body_bytes ->
        put_change(changeset, :body_text, String.slice(text, 0, @max_body_bytes))

      _ ->
        changeset
    end
  end
end
