defmodule CrmReactorWeb.AdminLive.IncomingEmails do
  use CrmReactorWeb, :live_view

  import CrmReactorWeb.AdminComponents
  import Ecto.Query

  alias CrmReactor.Emails.IncomingEmail
  alias CrmReactor.Repo
  alias Phoenix.LiveView.JS

  @impl true
  def mount(_params, _session, socket) do
    socket =
      assign(socket,
        page_title: "Incoming Emails",
        emails: [],
        expanded: nil,
        filter_status: "pending"
      )

    if connected?(socket) do
      {:ok, assign(socket, emails: list_emails("pending"))}
    else
      {:ok, socket}
    end
  end

  @impl true
  def handle_event("filter", %{"status" => status}, socket) do
    status = if status == "", do: nil, else: status
    {:noreply, assign(socket, filter_status: status, emails: list_emails(status), expanded: nil)}
  end

  @impl true
  def handle_event("toggle_status", %{"id" => id}, socket) do
    email = Repo.get!(IncomingEmail, id)
    new_status = if email.status == "pending", do: "completed", else: "pending"

    case email |> IncomingEmail.changeset(%{status: new_status}) |> Repo.update() do
      {:ok, _} ->
        {:noreply, assign(socket, emails: list_emails(socket.assigns.filter_status))}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Erreur lors de la mise à jour.")}
    end
  end

  @impl true
  def handle_event("toggle_expand", %{"id" => id}, socket) do
    id = String.to_integer(id)
    expanded = if socket.assigns.expanded == id, do: nil, else: id
    {:noreply, assign(socket, expanded: expanded)}
  end

  @impl true
  def handle_event("download_attachment", %{"key" => key}, socket) do
    if valid_storage_key?(key, socket.assigns.emails) do
      case CrmReactor.Storage.presigned_url(key) do
        {:ok, url} -> {:noreply, redirect(socket, external: url)}
        {:error, _} -> {:noreply, put_flash(socket, :error, "Could not generate download link.")}
      end
    else
      {:noreply, put_flash(socket, :error, "Invalid attachment.")}
    end
  end

  defp valid_storage_key?(key, emails) do
    Enum.any?(emails, fn email ->
      Enum.any?(email.attachments || [], fn att -> att["storage_key"] == key end)
    end)
  end

  defp format_size(nil), do: "?"
  defp format_size(bytes) when bytes < 1024, do: "#{bytes} B"
  defp format_size(bytes) when bytes < 1_048_576, do: "#{Float.round(bytes / 1024, 1)} KB"
  defp format_size(bytes), do: "#{Float.round(bytes / 1_048_576, 1)} MB"

  defp list_emails(status_filter) do
    query = from(e in IncomingEmail, order_by: [desc: e.received_at], limit: 100)

    query =
      if status_filter,
        do: where(query, [e], e.status == ^status_filter),
        else: query

    Repo.all(query)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.flash_group flash={@flash} />
    <h1>Incoming Emails</h1>
    <p style="color:#666;margin-bottom:20px;font-size:0.9rem;">
      Emails received via the inbound webhook. Click a row to view the body.
    </p>

    <form phx-change="filter" style="margin-bottom:16px;">
      <label style="font-size:0.8rem;font-weight:500;margin-right:8px;">Status</label>
      <select name="status" style="padding:8px 12px;border:1px solid #ddd;border-radius:6px;font-size:0.875rem;">
        <option value="">All</option>
        <option :for={s <- ["pending", "completed"]} value={s} selected={@filter_status == s}><%= s %></option>
      </select>
    </form>

    <div style="overflow-x:auto;max-height:70vh;overflow-y:auto;border-radius:8px;box-shadow:0 1px 3px rgba(0,0,0,0.06);">
    <table style="width:100%;border-collapse:collapse;background:#fff;">
      <thead style="position:sticky;top:0;background:#fff;z-index:1;">
        <tr>
          <th style="text-align:left;padding:10px 16px;font-size:0.8rem;font-weight:500;color:#666;border-bottom:1px solid #eee;width:180px;max-width:180px;">From</th>
          <th style="text-align:left;padding:10px 16px;font-size:0.8rem;font-weight:500;color:#666;border-bottom:1px solid #eee;">Subject</th>
          <th style="text-align:center;padding:10px 16px;font-size:0.8rem;font-weight:500;color:#666;border-bottom:1px solid #eee;width:80px;">Status</th>
          <th style="text-align:center;padding:10px 16px;font-size:0.8rem;font-weight:500;color:#666;border-bottom:1px solid #eee;width:80px;">Att.</th>
          <th style="text-align:right;padding:10px 16px;font-size:0.8rem;font-weight:500;color:#666;border-bottom:1px solid #eee;width:100px;">Received</th>
        </tr>
      </thead>
      <tbody>
        <%= if @emails == [] do %>
          <tr>
            <td colspan="5" style="padding:20px;text-align:center;color:#999;font-size:0.875rem;">
              Aucun email reçu.
            </td>
          </tr>
        <% end %>
        <%= for email <- @emails do %>
          <tr
            phx-click="toggle_expand"
            phx-value-id={email.id}
            style={"border-bottom:1px solid #f0f0f0;cursor:pointer;" <> if(@expanded == email.id, do: "background:#f9fafb;", else: "")}
          >
            <td style="padding:10px 16px;font-size:0.875rem;max-width:180px;overflow:hidden;text-overflow:ellipsis;white-space:nowrap;" title={email.from_address}><%= email.from_address %></td>
            <td style="padding:10px 16px;font-size:0.875rem;"><%= email.subject || "—" %></td>
            <td style="text-align:center;padding:10px 16px;">
              <span
                phx-click={JS.push("toggle_status", value: %{id: email.id})}
                style={"display:inline-block;padding:2px 10px;border-radius:12px;font-size:0.75rem;font-weight:500;cursor:pointer;" <>
                  if(email.status == "pending",
                    do: "background:#fef3c7;color:#92400e;",
                    else: "background:#d1fae5;color:#065f46;"
                  )}
              >
                <%= email.status %>
              </span>
            </td>
            <% att_count = length(email.attachments || []) %>
            <td style="text-align:center;padding:10px 16px;font-size:0.8rem;">
              <%= if att_count > 0 do %>
                <span style="display:inline-block;padding:2px 8px;border-radius:12px;font-size:0.75rem;font-weight:500;background:#e0e7ff;color:#3730a3;">
                  <%= att_count %>
                </span>
              <% end %>
            </td>
            <td style="text-align:right;padding:10px 16px;font-size:0.8rem;color:#666;">
              <%= Calendar.strftime(email.received_at, "%d/%m %H:%M") %>
            </td>
          </tr>
          <%= if @expanded == email.id do %>
            <tr style="background:#f9fafb;">
              <td colspan="5" style="padding:12px 16px;">
                <pre style="white-space:pre-wrap;font-size:0.8rem;color:#374151;max-height:300px;overflow-y:auto;"><%= email.body_text || "(no body)" %></pre>
                <%= if length(email.attachments || []) > 0 do %>
                  <div style="margin-top:10px;padding-top:10px;border-top:1px solid #e5e7eb;">
                    <strong style="font-size:0.8rem;color:#374151;">Attachments:</strong>
                    <ul style="margin:4px 0 0;padding-left:20px;font-size:0.8rem;color:#6b7280;">
                      <%= for att <- email.attachments do %>
                        <li>
                          <%= if att["storage_key"] do %>
                            <a
                              href="#"
                              phx-click="download_attachment"
                              phx-value-key={att["storage_key"]}
                              style="color:#4f46e5;text-decoration:underline;"
                            ><%= att["original_filename"] %></a>
                          <% else %>
                            <%= att["original_filename"] %>
                          <% end %>
                          (<%= att["content_type"] %>, <%= format_size(att["size"]) %>)
                        </li>
                      <% end %>
                    </ul>
                  </div>
                <% end %>
              </td>
            </tr>
          <% end %>
        <% end %>
      </tbody>
    </table>
    </div>
    """
  end
end
