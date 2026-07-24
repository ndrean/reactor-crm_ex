defmodule CrmReactorWeb.InboundEmailController do
  use CrmReactorWeb, :controller

  alias CrmReactor.Emails.IncomingEmail
  alias CrmReactor.Repo
  alias CrmReactor.Storage

  @max_total_bytes 10 * 1024 * 1024
  @max_attachment_count 20

  # Authentication is handled by WebhookSignature plug in the router pipeline.
  def create(conn, params) do
    handle_email(conn, params)
  end

  defp handle_email(conn, %{"from" => from} = params) when is_binary(from) do
    attachments_raw = params["attachments"] || []

    case store_attachments(attachments_raw) do
      {:ok, attachment_metas} ->
        attrs = %{
          from_address: from,
          subject: params["subject"],
          body_text: params["body"],
          received_at: DateTime.utc_now() |> DateTime.truncate(:second),
          attachments: attachment_metas
        }

        case %IncomingEmail{} |> IncomingEmail.changeset(attrs) |> Repo.insert() do
          {:ok, _email} ->
            json(conn, %{ok: true})

          {:error, _changeset} ->
            cleanup_stored(attachment_metas)
            conn |> put_status(422) |> json(%{error: "Invalid data"})
        end

      {:error, reason} ->
        conn |> put_status(422) |> json(%{error: reason})
    end
  end

  defp handle_email(conn, _params) do
    conn |> put_status(400) |> json(%{error: "Missing required field: from"})
  end

  defp store_attachments(raw_attachments) when is_list(raw_attachments) do
    if length(raw_attachments) > @max_attachment_count do
      {:error, "Too many attachments (max #{@max_attachment_count})"}
    else
      store_attachments_loop(raw_attachments, 0, [])
    end
  end

  defp store_attachments(_), do: {:ok, []}

  defp store_attachments_loop([], _total, acc), do: {:ok, Enum.reverse(acc)}

  defp store_attachments_loop([att | rest], total_bytes, acc) do
    with {:ok, content} <- decode_base64(att["content"]),
         new_total = total_bytes + byte_size(content),
         :ok <- check_total_size(new_total),
         filename = att["filename"] || "attachment",
         content_type = att["mimeType"] || "application/octet-stream",
         {:ok, storage_key} <- Storage.put("inbound", filename, content) do
      meta = %{
        "original_filename" => filename,
        "storage_key" => storage_key,
        "content_type" => content_type,
        "size" => byte_size(content)
      }

      store_attachments_loop(rest, new_total, [meta | acc])
    else
      {:error, :file_too_large} ->
        cleanup_stored(acc)
        {:error, "Attachment exceeds 5MB limit"}

      {:error, :total_size_exceeded} ->
        cleanup_stored(acc)
        {:error, "Total attachments exceed 10MB limit"}

      {:error, :invalid_base64} ->
        cleanup_stored(acc)
        {:error, "Invalid base64 attachment content"}

      {:error, _reason} ->
        cleanup_stored(acc)
        {:error, "Failed to store attachment"}
    end
  end

  defp decode_base64(nil), do: {:error, :invalid_base64}
  defp decode_base64(""), do: {:error, :invalid_base64}

  defp decode_base64(data) when is_binary(data) do
    case Base.decode64(data) do
      {:ok, content} -> {:ok, content}
      :error -> {:error, :invalid_base64}
    end
  end

  defp decode_base64(_), do: {:error, :invalid_base64}

  defp check_total_size(total) when total > @max_total_bytes, do: {:error, :total_size_exceeded}
  defp check_total_size(_), do: :ok

  defp cleanup_stored(metas) do
    Enum.each(metas, fn
      %{"storage_key" => key} -> Storage.delete(key)
      _ -> :ok
    end)
  end
end
