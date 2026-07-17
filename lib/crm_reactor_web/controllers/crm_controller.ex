defmodule CrmReactorWeb.CrmController do
  use CrmReactorWeb, :controller

  alias CrmReactor.CRM.ExecutionLog
  alias CrmReactor.Reactors.MasterIngest
  alias CrmReactor.Reactors.Modules.Mutations
  alias CrmReactor.Repo
  alias CrmReactor.Tenants.TenantCache

  require Logger
  import Ecto.Query

  def ingest(conn, %{"user_id" => user_id, "text" => text}) do
    case TenantCache.lookup(user_id) do
      {:error, :unknown_user} ->
        conn |> put_status(403) |> json(%{error: "Unknown user"})

      {:ok, tenant} ->
        input = %{
          user_id: user_id,
          raw_input: text,
          is_audio: false,
          channel: :http,
          job_id: "http-#{Ecto.UUID.generate()}",
          attachment: nil,
          tenant: tenant
        }

        case Reactor.run(MasterIngest, input) do
          {:ok, result} ->
            json(conn, format_result(result))

          # coveralls-ignore-next-line
          {:error, reason} ->
            Logger.error("Ingest failed: #{inspect(reason)}")
            mark_log_failed(input, reason)
            conn |> put_status(500) |> json(%{error: "Internal server error"})
        end
    end
  end

  def confirm(conn, %{"pending_id" => pending_id, "decision" => decision, "user_id" => user_id})
      when is_binary(user_id) do
    case Mutations.confirm(pending_id, decision, user_id) do
      {:ok, result} ->
        json(conn, format_result(result))

      {:error, :pending_not_found} ->
        conn |> put_status(404) |> json(%{error: "Pending action not found"})

      {:error, :unauthorized} ->
        conn |> put_status(403) |> json(%{error: "Unauthorized"})

      {:error, :invalid_email} ->
        conn |> put_status(400) |> json(%{error: "Invalid email address"})

      {:error, :invalid_decision} ->
        conn |> put_status(400) |> json(%{error: "Invalid decision"})

      # coveralls-ignore-next-line
      {:error, reason} ->
        Logger.error("Confirm failed: #{inspect(reason)}")
        conn |> put_status(500) |> json(%{error: "Internal server error"})
    end
  end

  def confirm(conn, _params) do
    conn |> put_status(400) |> json(%{error: "pending_id, decision, and user_id required"})
  end

  defp mark_log_failed(%{job_id: job_id, user_id: user_id}, reason) do
    error_msg =
      case reason do
        %{errors: [%{error: err} | _]} -> inspect(err)
        other -> inspect(other)
      end

    with {:ok, %{schema_name: schema}} <- TenantCache.lookup(user_id),
         %ExecutionLog{} = log <-
           Repo.one(from(l in ExecutionLog, where: l.job_id == ^job_id), prefix: schema) do
      log
      |> ExecutionLog.error_changeset(%{error_message: error_msg})
      |> Repo.update()
    end
  rescue
    _ -> :ok
  end

  defp format_result(%{output: output, action: action} = result) do
    base = %{
      output: output,
      action: action,
      ai_assisted: true,
      model: result[:model] || "mistral-small-latest"
    }

    if pending_id = result[:pending_id], do: Map.put(base, :pending_id, pending_id), else: base
  end
end
