defmodule CrmReactor.Workers.IngestWorker do
  @moduledoc "Oban worker: runs the MasterIngest Reactor pipeline asynchronously."
  use Oban.Worker, queue: :ingest, max_attempts: 3

  alias CrmReactor.CRM.ExecutionLog
  alias CrmReactor.Reactors.MasterIngest
  alias CrmReactor.Repo
  alias CrmReactor.Telegram
  alias CrmReactor.Tenants.TenantCache

  import Ecto.Query

  @impl true
  def perform(%Oban.Job{id: job_id, args: args}) do
    input = %{
      user_id: args["user_id"],
      raw_input: args["text"],
      is_audio: args["is_audio"] || false,
      channel: to_channel(args["channel"]),
      job_id: "oban-#{job_id}",
      attachment: nil,
      tenant_override: nil
    }

    case Reactor.run(MasterIngest, input) do
      {:ok, result} ->
        case maybe_send_reply(args["channel"], args["chat_id"], result) do
          {:error, reason} -> {:error, {:send_failed, reason}}
          _ -> :ok
        end

      {:error, reason} ->
        mark_log_failed(input, reason)
        {:error, reason}
    end
  end

  defp mark_log_failed(%{job_id: job_id, user_id: user_id} = input, reason) do
    error_msg = format_error(reason)

    case resolve_schema(user_id) do
      nil ->
        :ok

      schema ->
        case Repo.one(from(l in ExecutionLog, where: l.job_id == ^job_id), prefix: schema) do
          nil ->
            %ExecutionLog{}
            |> ExecutionLog.create_changeset(%{
              triggered_by: user_id,
              channel: to_string(input.channel),
              raw_input: input.raw_input,
              job_id: job_id
            })
            |> ExecutionLog.error_changeset(%{error_message: error_msg})
            |> Repo.insert(prefix: schema)

          log ->
            log
            |> ExecutionLog.error_changeset(%{error_message: error_msg})
            |> Repo.update(prefix: schema)
        end
    end
  end

  defp resolve_schema(user_id) do
    case TenantCache.lookup(user_id) do
      {:ok, %{schema_name: schema}} -> schema
      {:error, :unknown_user} -> nil
    end
  end

  defp to_channel("http"), do: :http
  defp to_channel("telegram"), do: :telegram

  defp format_error(%{errors: [%{error: error} | _]}), do: inspect(error)
  defp format_error(reason), do: inspect(reason)

  defp maybe_send_reply("telegram", chat_id, result) when is_binary(chat_id) do
    output = extract_output(result)
    client = Application.get_env(:crm_reactor, :telegram_client, Telegram)

    case result do
      %{pending_id: pending_id} when not is_nil(pending_id) ->
        client.send_confirmation(chat_id, output, pending_id)

      _ ->
        client.send_message(chat_id, output)
    end
  end

  defp maybe_send_reply(_, _, _), do: :ok

  defp extract_output(%{output: output}), do: output
  defp extract_output(_result), do: "Traitement terminé."
end
