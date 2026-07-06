defmodule CrmReactor.Reactors.Steps.LogExecution do
  @moduledoc "Reactor step: create an execution log entry for audit. Idempotent on retries via job_id."
  use Reactor.Step

  alias CrmReactor.CRM.ExecutionLog
  alias CrmReactor.Repo

  import Ecto.Query

  @impl true
  def run(
        %{tenant: tenant, raw_input: raw_input, channel: channel, user_id: user_id} = args,
        _context,
        _options
      ) do
    job_id = args[:job_id]

    if job_id do
      upsert_log(tenant.schema_name, %{
        triggered_by: user_id,
        channel: to_string(channel),
        raw_input: raw_input,
        job_id: job_id
      })
    else
      %ExecutionLog{}
      |> ExecutionLog.create_changeset(%{
        triggered_by: user_id,
        channel: to_string(channel),
        raw_input: raw_input
      })
      |> Repo.insert(prefix: tenant.schema_name)
    end
  end

  defp upsert_log(schema, attrs) do
    case Repo.one(from(l in ExecutionLog, where: l.job_id == ^attrs.job_id), prefix: schema) do
      nil ->
        %ExecutionLog{}
        |> ExecutionLog.create_changeset(attrs)
        |> Repo.insert(prefix: schema)

      existing ->
        existing
        |> Ecto.Changeset.change(status: "processing", error_message: nil, completed_at: nil)
        |> Repo.update(prefix: schema)
    end
  end
end
