defmodule CrmReactor.CRM.ExecutionAttachment do
  use Ecto.Schema
  import Ecto.Changeset

  schema "execution_attachments" do
    field :execution_log_id, :integer
    field :filename, :string
    field :content_type, :string
    field :size_bytes, :integer
    field :storage_key, :string

    timestamps(type: :utc_datetime, inserted_at: :created_at, updated_at: false)
  end

  def changeset(attachment, attrs) do
    attachment
    |> cast(attrs, [:execution_log_id, :filename, :content_type, :size_bytes, :storage_key])
    |> validate_required([:filename, :size_bytes, :storage_key])
  end
end
