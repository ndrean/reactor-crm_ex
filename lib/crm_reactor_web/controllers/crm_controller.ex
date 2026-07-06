defmodule CrmReactorWeb.CrmController do
  use CrmReactorWeb, :controller

  alias CrmReactor.Reactors.MasterIngest
  alias CrmReactor.Reactors.Modules.Mutations

  def ingest(conn, %{"user_id" => user_id, "text" => text}) do
    input = %{
      user_id: user_id,
      raw_input: text,
      is_audio: false,
      channel: :http,
      job_id: "http-#{Ecto.UUID.generate()}",
      attachment: nil
    }

    case Reactor.run(MasterIngest, input) do
      {:ok, result} ->
        json(conn, format_result(result))

      {:error, %{errors: [%{error: :unknown_user} | _]}} ->
        conn |> put_status(403) |> json(%{error: "Unknown user"})

      {:error, reason} ->
        conn |> put_status(500) |> json(%{error: inspect(reason)})
    end
  end

  def confirm(conn, %{"pending_id" => pending_id, "decision" => decision}) do
    case Mutations.confirm(pending_id, decision) do
      {:ok, result} ->
        json(conn, format_result(result))

      {:error, :pending_not_found} ->
        conn |> put_status(404) |> json(%{error: "Pending action not found"})

      {:error, :invalid_email} ->
        conn |> put_status(400) |> json(%{error: "Invalid email address"})

      {:error, reason} ->
        conn |> put_status(500) |> json(%{error: inspect(reason)})
    end
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

  defp format_result(result) when is_map(result), do: result
end
