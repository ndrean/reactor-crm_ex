defmodule CrmReactorWeb.WebhookController do
  use CrmReactorWeb, :controller

  require Logger

  alias CrmReactor.Telegram.Handler

  def telegram(conn, params) do
    expected = Application.get_env(:crm_reactor, :telegram_secret_token)

    case get_req_header(conn, "x-telegram-bot-api-secret-token") do
      [token] when is_binary(token) and is_binary(expected) ->
        if Plug.Crypto.secure_compare(token, expected) do
          Handler.on_update(decode_update(params))
          json(conn, %{ok: true})
        else
          conn |> put_status(401) |> json(%{error: "Invalid secret token"})
        end

      _ ->
        conn |> put_status(401) |> json(%{error: "Invalid secret token"})
    end
  end

  # Text message
  defp decode_update(%{"message" => %{"text" => text, "chat" => %{"id" => chat_id}}})
       when is_binary(text) do
    %{message: %{text: text, chat: %{id: chat_id}}}
  end

  # Voice message
  defp decode_update(%{"message" => %{"voice" => voice, "chat" => %{"id" => chat_id}}})
       when is_map(voice) do
    %{message: %{voice: %{file_id: voice["file_id"]}, chat: %{id: chat_id}}}
  end

  # Callback query
  defp decode_update(%{
         "callback_query" => %{
           "id" => cq_id,
           "data" => data,
           "message" => %{"chat" => %{"id" => chat_id}}
         }
       }) do
    %{callback_query: %{id: cq_id, data: data, message: %{chat: %{id: chat_id}}}}
  end

  defp decode_update(params) do
    Logger.warning("Unrecognized Telegram update: #{inspect(Map.keys(params))}")
    %{}
  end
end
