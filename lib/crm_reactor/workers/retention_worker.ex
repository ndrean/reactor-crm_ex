defmodule CrmReactor.Workers.RetentionWorker do
  @moduledoc "Oban cron worker: anonymizes execution_logs older than the retention period."
  use Oban.Worker, queue: :maintenance, max_attempts: 1

  require Logger

  alias CrmReactor.Repo
  alias CrmReactor.Tenants.Tenant

  @retention_days 180

  @impl true
  def perform(_job) do
    cutoff =
      DateTime.utc_now()
      |> DateTime.add(-@retention_days * 86_400)
      |> DateTime.truncate(:second)

    schemas = Repo.all(Tenant) |> Enum.map(& &1.schema_name)

    for schema <- schemas, safe_schema?(schema) do
      %{num_rows: count} =
        Repo.query!(
          """
          UPDATE #{schema}.execution_logs
          SET raw_input = '[RETAINED]',
              output = '[RETAINED]',
              error_message = NULL,
              proposed_params = NULL
          WHERE logged_at < $1
            AND status != 'erased'
            AND raw_input != '[RETAINED]'
          """,
          [cutoff]
        )

      if count > 0 do
        Logger.info("Retention: anonymized #{count} logs in #{schema}")
      end
    end

    :ok
  end

  defp safe_schema?(name), do: Regex.match?(~r/\A[a-z_][a-z0-9_]*\z/, name)
end
