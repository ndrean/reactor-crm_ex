defmodule CrmReactorWeb.WebhookController do
  use CrmReactorWeb, :controller

  alias CrmReactor.Telegram.Handler

  def telegram(conn, params) do
    secret = Application.get_env(:crm_reactor, :telegram_secret_token)

    case get_req_header(conn, "x-telegram-bot-api-secret-token") do
      [^secret] ->
        Handler.on_update(decode_update(params))
        json(conn, %{ok: true})

      _ ->
        conn |> put_status(401) |> json(%{error: "Invalid secret token"})
    end
  end

  defp decode_update(params) do
    Jason.encode!(params)
    |> Jason.decode!(keys: :atoms)
    |> then(&struct(Telegex.Type.Update, &1))
  rescue
    _ -> %{}
  end
end
