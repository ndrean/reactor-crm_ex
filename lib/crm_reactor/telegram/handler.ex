defmodule CrmReactor.Telegram.Handler do
  @moduledoc "Telegex webhook handler: text, voice, and callback query processing."
  use Telegex.Hook.GenHandler

  alias CrmReactor.Reactors.Modules.Mutations
  alias CrmReactor.Telegram
  alias CrmReactor.Workers.IngestWorker

  @impl true
  def on_boot do
    %Telegex.Hook.Config{
      server_port: 4001,
      secret_token: Application.get_env(:crm_reactor, :telegram_secret_token)
    }
  end

  @impl true
  def on_update(%{message: %{text: text, chat: %{id: chat_id}}} = _update) when is_binary(text) do
    %{
      "user_id" => to_string(chat_id),
      "text" => text,
      "channel" => "telegram",
      "chat_id" => to_string(chat_id),
      "is_audio" => false
    }
    |> IngestWorker.new()
    |> Oban.insert()
    |> log_insert_error(chat_id)

    :ok
  end

  def on_update(%{message: %{voice: voice, chat: %{id: chat_id}}}) when not is_nil(voice) do
    case Telegex.get_file(voice.file_id) do
      {:ok, file} ->
        token = Application.fetch_env!(:crm_reactor, :telegram_bot_token)
        audio_url = "https://api.telegram.org/file/bot#{token}/#{file.file_path}"

        %{
          "user_id" => to_string(chat_id),
          "text" => audio_url,
          "channel" => "telegram",
          "chat_id" => to_string(chat_id),
          "is_audio" => true
        }
        |> IngestWorker.new()
        |> Oban.insert()
        |> log_insert_error(chat_id)

      {:error, reason} ->
        require Logger
        Logger.warning("Failed to get voice file: #{inspect(reason)}")
        Telegram.send_message(to_string(chat_id), "Impossible de traiter le message vocal.")
    end

    :ok
  end

  def on_update(%{callback_query: %{data: data, message: %{chat: %{id: chat_id}}} = cq}) do
    [pending_id, decision] = String.split(data, ":")

    case Mutations.confirm(pending_id, decision, to_string(chat_id)) do
      {:ok, %{output: output}} ->
        Telegram.send_message(to_string(chat_id), output)

      {:error, :unauthorized} ->
        Telegram.send_message(to_string(chat_id), "Action non autorisée.")

      {:error, _} ->
        Telegram.send_message(to_string(chat_id), "Action expirée ou introuvable.")
    end

    Telegex.answer_callback_query(cq.id)
    :ok
  end

  def on_update(_update), do: :ok

  defp log_insert_error({:ok, _}, _chat_id), do: :ok

  defp log_insert_error({:error, reason}, chat_id) do
    require Logger
    Logger.error("Failed to enqueue ingest job for chat_id=#{chat_id}: #{inspect(reason)}")
  end
end
