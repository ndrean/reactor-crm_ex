defmodule CrmReactor.Telegram.Handler do
  @moduledoc "Telegex webhook handler: text, voice, and callback query processing."
  use Telegex.Hook.GenHandler

  require Logger

  alias CrmReactor.Accounts
  alias CrmReactor.Reactors.Modules.Mutations
  alias CrmReactor.Telegram
  alias CrmReactor.Tenants.TenantCache
  alias CrmReactor.Workers.IngestWorker

  @impl true
  def on_boot do
    %Telegex.Hook.Config{
      server_port: 4001,
      secret_token: Application.get_env(:crm_reactor, :telegram_secret_token)
    }
  end

  @impl true
  def on_update(%{message: %{text: "/calendar", chat: %{id: chat_id}}}) do
    chat_id_str = to_string(chat_id)

    with {:ok, %{schema_name: _}} <- TenantCache.lookup(chat_id_str),
         email when is_binary(email) <- TenantCache.resolve_canonical_id(chat_id_str),
         %{} = account <- Accounts.get_account_by_email(email),
         {:ok, token} <- Accounts.get_or_create_calendar_token(account) do
      url = "#{CrmReactorWeb.Endpoint.url()}/cal/#{token}"

      Telegram.send_message(
        chat_id_str,
        """
        📅 Votre calendrier CRM :
        #{url}

        Pour l'ajouter :
        • Google Calendar → Autres agendas → À partir de l'URL → coller
        • Apple Calendar → Fichier → Nouvel abonnement → coller
        • Outlook → Ajouter un calendrier → À partir d'Internet → coller

        Le calendrier se met à jour automatiquement.\
        """
      )
    else
      _ ->
        Telegram.send_message(chat_id_str, "Aucun compte trouvé. Contactez votre administrateur.")
    end

    :ok
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

  def on_update(%{message: %{photo: photos, chat: %{id: chat_id}} = msg})
      when is_list(photos) and photos != [] do
    # Telegram sends multiple sizes; last is the largest
    largest = List.last(photos)
    caption = msg[:caption] || ""

    case download_telegram_file(largest.file_id) do
      {:ok, content, file_path} ->
        filename = Path.basename(file_path)
        chat_id_str = to_string(chat_id)

        case store_and_enqueue(chat_id_str, caption, filename, "image/jpeg", content) do
          {:ok, _} -> :ok
          {:error, reason} -> log_insert_error({:error, reason}, chat_id)
        end

      {:error, reason} ->
        Logger.warning("Failed to download photo: #{inspect(reason)}")
        Telegram.send_message(to_string(chat_id), "Impossible de traiter l'image.")
    end

    :ok
  end

  def on_update(%{message: %{document: doc, chat: %{id: chat_id}} = msg}) when not is_nil(doc) do
    caption = msg[:caption] || ""

    case download_telegram_file(doc.file_id) do
      {:ok, content, _file_path} ->
        filename = doc.file_name || "document"
        content_type = doc.mime_type || "application/octet-stream"
        chat_id_str = to_string(chat_id)

        case store_and_enqueue(chat_id_str, caption, filename, content_type, content) do
          {:ok, _} -> :ok
          {:error, reason} -> log_insert_error({:error, reason}, chat_id)
        end

      {:error, reason} ->
        Logger.warning("Failed to download document: #{inspect(reason)}")
        Telegram.send_message(to_string(chat_id), "Impossible de traiter le fichier.")
    end

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
        Logger.warning("Failed to get voice file: #{inspect(reason)}")
        Telegram.send_message(to_string(chat_id), "Impossible de traiter le message vocal.")
    end

    :ok
  end

  def on_update(%{callback_query: %{data: data, message: %{chat: %{id: chat_id}}} = cq}) do
    [pending_id, decision] = String.split(data, ":")
    user_id = TenantCache.resolve_canonical_id(to_string(chat_id)) || to_string(chat_id)

    case Mutations.confirm(pending_id, decision, user_id) do
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

  defp download_telegram_file(file_id) do
    with {:ok, file} <- Telegex.get_file(file_id) do
      token = Application.fetch_env!(:crm_reactor, :telegram_bot_token)
      url = "https://api.telegram.org/file/bot#{token}/#{file.file_path}"

      case Req.get(url, max_retries: 1, receive_timeout: 30_000) do
        {:ok, %{status: 200, body: body}} when is_binary(body) ->
          {:ok, body, file.file_path}

        {:ok, %{status: status}} ->
          {:error, {:http_error, status}}

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  defp store_and_enqueue(chat_id_str, caption, filename, content_type, content) do
    case TenantCache.lookup(chat_id_str) do
      {:ok, %{schema_name: schema}} ->
        case CrmReactor.Storage.put(schema, filename, content) do
          {:ok, storage_key} ->
            attachment = %{
              "storage_key" => storage_key,
              "filename" => filename,
              "content_type" => content_type,
              "size_bytes" => byte_size(content)
            }

            text = if caption == "", do: "fichier joint", else: caption

            %{
              "user_id" => chat_id_str,
              "text" => text,
              "channel" => "telegram",
              "chat_id" => chat_id_str,
              "is_audio" => false,
              "attachment" => attachment
            }
            |> IngestWorker.new()
            |> Oban.insert()

          {:error, reason} ->
            {:error, reason}
        end

      error ->
        error
    end
  end

  defp log_insert_error({:ok, _}, _chat_id), do: :ok

  defp log_insert_error({:error, reason}, chat_id) do
    Logger.error("Failed to enqueue ingest job for chat_id=#{chat_id}: #{inspect(reason)}")
  end
end
