defmodule CrmReactor.Workers.FileCleanupWorker do
  @moduledoc """
  Oban cron worker: deletes stored files linked to execution_logs older than the retention period.

  Runs after RetentionWorker (which anonymizes log text). This worker removes the actual
  files from storage and deletes the execution_attachment DB records.
  """
  use Oban.Worker, queue: :maintenance, max_attempts: 1

  import Ecto.Query

  alias CrmReactor.Repo
  alias CrmReactor.Storage
  alias CrmReactor.Tenants.Tenant

  require Logger

  @retention_days 180

  @impl true
  def perform(_job) do
    cutoff =
      DateTime.utc_now()
      |> DateTime.add(-@retention_days * 86_400)
      |> DateTime.truncate(:second)

    schemas = Repo.all(Tenant) |> Enum.map(& &1.schema_name)

    total =
      Enum.reduce(schemas, 0, fn schema, acc ->
        acc + cleanup_schema(schema, cutoff)
      end)

    if total > 0 do
      Logger.info("FileCleanup: deleted #{total} expired files")
    end

    :ok
  end

  defp cleanup_schema(schema, cutoff) do
    # Find attachments linked to old execution_logs
    attachments =
      Repo.all(
        from(a in {"execution_attachments", CrmReactor.CRM.ExecutionAttachment},
          join: e in "execution_logs",
          on: a.execution_log_id == e.id,
          where: e.logged_at < ^cutoff,
          select: %{id: a.id, storage_key: a.storage_key}
        ),
        prefix: schema
      )

    Enum.reduce(attachments, 0, fn attachment, count ->
      case Storage.delete(attachment.storage_key) do
        :ok ->
          Repo.delete_all(
            from(a in {"execution_attachments", CrmReactor.CRM.ExecutionAttachment},
              where: a.id == ^attachment.id
            ),
            prefix: schema
          )

          count + 1

        {:error, reason} ->
          Logger.warning(
            "FileCleanup: failed to delete #{attachment.storage_key}: #{inspect(reason)}"
          )

          count
      end
    end)
  end
end
