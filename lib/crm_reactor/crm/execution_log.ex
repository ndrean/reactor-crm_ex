defmodule CrmReactor.CRM.ExecutionLog do
  use Ecto.Schema
  import Ecto.Changeset

  schema "execution_logs" do
    field :triggered_by, :string
    field :channel, :string
    field :raw_input, :string
    field :action, :string
    field :routing_path, :string
    field :module, :string
    field :status, :string, default: "processing"
    field :proposed_params, :map
    field :pending_id, Ecto.UUID
    field :prompt_tokens, :integer
    field :completion_tokens, :integer
    field :total_tokens, :integer
    field :output, :string
    field :error_message, :string
    field :generated_sql, :string
    field :job_id, :string
    field :logged_at, :utc_datetime
    field :completed_at, :utc_datetime
  end

  def create_changeset(log, attrs) do
    log
    |> cast(attrs, [:triggered_by, :channel, :raw_input, :job_id])
    |> put_change(:logged_at, DateTime.utc_now() |> DateTime.truncate(:second))
  end

  def complete_changeset(log, attrs) do
    log
    |> cast(attrs, [
      :action,
      :routing_path,
      :module,
      :status,
      :output,
      :prompt_tokens,
      :completion_tokens,
      :total_tokens,
      :generated_sql
    ])
    |> put_change(:completed_at, DateTime.utc_now() |> DateTime.truncate(:second))
    |> put_change(:status, "completed")
  end

  def pending_changeset(log, attrs) do
    log
    |> cast(attrs, [:action, :module, :proposed_params])
    |> put_change(:status, "pending")
    |> put_change(:pending_id, Ecto.UUID.generate())
  end

  def error_changeset(log, attrs) do
    log
    |> cast(attrs, [:error_message])
    |> put_change(:status, "error")
    |> put_change(:completed_at, DateTime.utc_now() |> DateTime.truncate(:second))
  end
end
