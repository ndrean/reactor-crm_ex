defmodule CrmReactorWeb.AdminLive.IncomingEmails do
  use CrmReactorWeb, :live_view

  import CrmReactorWeb.AdminComponents
  import Ecto.Query

  alias CrmReactor.Emails.IncomingEmail
  alias CrmReactor.Repo

  @impl true
  def mount(_params, _session, socket) do
    socket = assign(socket, page_title: "Incoming Emails", emails: [], expanded: nil)

    if connected?(socket) do
      {:ok, assign(socket, emails: list_emails())}
    else
      {:ok, socket}
    end
  end

  @impl true
  def handle_event("toggle_status", %{"id" => id}, socket) do
    email = Repo.get!(IncomingEmail, id)
    new_status = if email.status == "pending", do: "completed", else: "pending"

    case email |> IncomingEmail.changeset(%{status: new_status}) |> Repo.update() do
      {:ok, _} ->
        {:noreply, assign(socket, emails: list_emails())}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Erreur lors de la mise à jour.")}
    end
  end

  def handle_event("toggle_expand", %{"id" => id}, socket) do
    id = String.to_integer(id)
    expanded = if socket.assigns.expanded == id, do: nil, else: id
    {:noreply, assign(socket, expanded: expanded)}
  end

  defp list_emails do
    from(e in IncomingEmail, order_by: [desc: e.received_at], limit: 100)
    |> Repo.all()
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.flash_group flash={@flash} />
    <h1>Incoming Emails</h1>
    <p style="color:#666;margin-bottom:20px;font-size:0.9rem;">
      Emails received via the inbound webhook. Click a row to view the body.
    </p>

    <table style="width:100%;border-collapse:collapse;background:#fff;border-radius:8px;overflow:hidden;box-shadow:0 1px 3px rgba(0,0,0,0.06);">
      <thead>
        <tr>
          <th style="text-align:left;padding:10px 16px;font-size:0.8rem;font-weight:500;color:#666;border-bottom:1px solid #eee;">From</th>
          <th style="text-align:left;padding:10px 16px;font-size:0.8rem;font-weight:500;color:#666;border-bottom:1px solid #eee;">Subject</th>
          <th style="text-align:center;padding:10px 16px;font-size:0.8rem;font-weight:500;color:#666;border-bottom:1px solid #eee;">Status</th>
          <th style="text-align:right;padding:10px 16px;font-size:0.8rem;font-weight:500;color:#666;border-bottom:1px solid #eee;">Received</th>
        </tr>
      </thead>
      <tbody>
        <%= if @emails == [] do %>
          <tr>
            <td colspan="4" style="padding:20px;text-align:center;color:#999;font-size:0.875rem;">
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
            <td style="padding:10px 16px;font-size:0.875rem;"><%= email.from_address %></td>
            <td style="padding:10px 16px;font-size:0.875rem;"><%= email.subject || "—" %></td>
            <td style="text-align:center;padding:10px 16px;">
              <span
                phx-click="toggle_status"
                phx-value-id={email.id}
                style={"display:inline-block;padding:2px 10px;border-radius:12px;font-size:0.75rem;font-weight:500;cursor:pointer;" <>
                  if(email.status == "pending",
                    do: "background:#fef3c7;color:#92400e;",
                    else: "background:#d1fae5;color:#065f46;"
                  )}
              >
                <%= email.status %>
              </span>
            </td>
            <td style="text-align:right;padding:10px 16px;font-size:0.8rem;color:#666;">
              <%= Calendar.strftime(email.received_at, "%d/%m %H:%M") %>
            </td>
          </tr>
          <%= if @expanded == email.id do %>
            <tr style="background:#f9fafb;">
              <td colspan="4" style="padding:12px 16px;">
                <pre style="white-space:pre-wrap;font-size:0.8rem;color:#374151;max-height:300px;overflow-y:auto;"><%= email.body_text || "(no body)" %></pre>
              </td>
            </tr>
          <% end %>
        <% end %>
      </tbody>
    </table>
    """
  end
end
