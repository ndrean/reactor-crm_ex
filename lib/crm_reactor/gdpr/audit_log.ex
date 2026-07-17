defmodule CrmReactor.GDPR.AuditLog do
  @moduledoc "Records GDPR operations (export, erasure) for compliance audit trail."

  use Ecto.Schema
  import Ecto.Changeset

  alias CrmReactor.Repo

  @schema_prefix "global_registry"

  schema "gdpr_audit_log" do
    field :action, :string
    field :subject_id, :string
    field :performed_by, :string
    field :details, :map
    field :performed_at, :utc_datetime_usec
  end

  @required ~w(action subject_id performed_by)a

  def changeset(log \\ %__MODULE__{}, attrs) do
    log
    |> cast(attrs, @required ++ [:details])
    |> validate_required(@required)
    |> validate_inclusion(:action, ~w(export email_export erase erase_contact))
  end

  @doc "Log a GDPR operation. Fire-and-forget — never fails the caller."
  def record(action, subject_id, performed_by, details \\ nil) do
    %{action: action, subject_id: subject_id, performed_by: performed_by, details: details}
    |> changeset()
    |> Repo.insert()
  rescue
    _ -> :ok
  end
end
