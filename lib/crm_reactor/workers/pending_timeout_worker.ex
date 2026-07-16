defmodule CrmReactor.Workers.PendingTimeoutWorker do
  @moduledoc "Oban worker: auto-rejects pending mutations after timeout."
  use Oban.Worker, queue: :mutations, max_attempts: 1

  alias CrmReactor.Reactors.Modules.Mutations

  @impl true
  def perform(%Oban.Job{args: %{"pending_id" => pending_id, "schema_name" => schema}}) do
    case Mutations.confirm_system(pending_id, "reject", schema) do
      {:ok, _} -> :ok
      {:error, :pending_not_found} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  # Fallback for jobs enqueued before this change (no schema_name in args)
  def perform(%Oban.Job{args: %{"pending_id" => pending_id}}) do
    case Mutations.confirm(pending_id, "reject") do
      {:ok, _} -> :ok
      {:error, :pending_not_found} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end
end
