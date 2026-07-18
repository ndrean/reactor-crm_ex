defmodule CrmReactor.Reactors.PendingHelper do
  @moduledoc "Shared helper for scheduling pending mutation timeouts."

  alias CrmReactor.Workers.PendingTimeoutWorker

  require Logger

  @pending_timeout_seconds 15 * 60

  @doc "Schedules an Oban job to auto-reject a pending mutation after 15 minutes."
  def schedule_pending_timeout(pending_id, schema) do
    case %{"pending_id" => pending_id, "schema_name" => schema}
         |> PendingTimeoutWorker.new(schedule_in: @pending_timeout_seconds)
         |> Oban.insert() do
      {:ok, _job} ->
        :ok

      {:error, reason} ->
        Logger.error("Failed to schedule pending timeout for #{pending_id}: #{inspect(reason)}")
        :ok
    end
  end
end
