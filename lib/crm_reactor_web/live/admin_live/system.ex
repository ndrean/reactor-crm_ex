defmodule CrmReactorWeb.AdminLive.System do
  use CrmReactorWeb, :live_view

  import CrmReactorWeb.AdminComponents
  import Ecto.Query

  alias CrmReactor.Accounts.Account
  alias CrmReactor.Repo
  alias CrmReactor.Telegram
  alias CrmReactorWeb.Endpoint

  @impl true
  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(
        page_title: "System",
        webhook_info: nil,
        webhook_loading: false,
        admins: [],
        confirm_fix: false
      )

    if connected?(socket) do
      {:ok, load_system_info(socket)}
    else
      {:ok, socket}
    end
  end

  defp load_system_info(socket) do
    admins =
      from(a in Account, where: a.role == "admin", order_by: [asc: a.inserted_at])
      |> Repo.all()

    webhook_info = fetch_webhook_info()

    assign(socket,
      admins: admins,
      webhook_info: webhook_info
    )
  end

  defp fetch_webhook_info do
    case Telegram.webhook_info() do
      {:ok, info} -> info
      {:error, _} -> nil
    end
  end

  @impl true
  def handle_event("refresh_webhook", _params, socket) do
    {:noreply, assign(socket, webhook_info: fetch_webhook_info())}
  end

  def handle_event("fix_webhook", _params, socket) do
    {:noreply, assign(socket, confirm_fix: true)}
  end

  def handle_event("confirm_fix_webhook", _params, socket) do
    expected_url = "#{Endpoint.url()}/webhook/telegram"

    case Telegram.set_webhook_url(expected_url) do
      {:ok, true} ->
        {:noreply,
         socket
         |> assign(webhook_info: fetch_webhook_info(), confirm_fix: false)
         |> put_flash(:info, "Webhook set to #{expected_url}")}

      {:error, reason} ->
        {:noreply,
         socket
         |> assign(confirm_fix: false)
         |> put_flash(:error, "Failed: #{inspect(reason)}")}
    end
  end

  def handle_event("cancel_fix_webhook", _params, socket) do
    {:noreply, assign(socket, confirm_fix: false)}
  end

  @impl true
  def render(assigns) do
    assigns =
      assigns
      |> assign_new(:expected_webhook_url, fn -> "#{Endpoint.url()}/webhook/telegram" end)
      |> assign_new(:base_url, fn -> Endpoint.url() end)
      |> assign_new(:phx_host, fn ->
        Application.get_env(:crm_reactor, CrmReactorWeb.Endpoint)[:url][:host] || "localhost"
      end)
      |> assign_new(:calendar_url_template, fn -> "#{Endpoint.url()}/cal/{token}" end)
      |> assign_new(:bot_token_masked, fn ->
        case Application.get_env(:crm_reactor, :telegram_bot_token) do
          nil ->
            "not configured"

          token when is_binary(token) and byte_size(token) > 8 ->
            "#{String.slice(token, 0..3)}...#{String.slice(token, -4..-1//1)}"

          _ ->
            "configured"
        end
      end)

    ~H"""
    <.flash_group flash={@flash} />
    <h1>System Status</h1>

    <%!-- Domain Section --%>
    <div style="background:#fff;padding:20px 24px;border-radius:8px;box-shadow:0 1px 3px rgba(0,0,0,0.06);margin-bottom:24px;">
      <h2 style="margin:0 0 16px;font-size:1.1rem;font-weight:600;">Domain Configuration</h2>
      <div style="display:grid;grid-template-columns:160px 1fr;gap:8px 16px;font-size:0.9rem;">
        <span style="color:#666;font-weight:500;">PHX_HOST</span>
        <span><code><%= @phx_host %></code></span>

        <span style="color:#666;font-weight:500;">Base URL</span>
        <span><code><%= @base_url %></code></span>

        <span style="color:#666;font-weight:500;">Calendar Feed</span>
        <span><code><%= @calendar_url_template %></code></span>
      </div>
    </div>

    <%!-- Telegram Webhook Section --%>
    <div style="background:#fff;padding:20px 24px;border-radius:8px;box-shadow:0 1px 3px rgba(0,0,0,0.06);margin-bottom:24px;">
      <h2 style="margin:0 0 16px;font-size:1.1rem;font-weight:600;">Telegram Webhook</h2>

      <div style="display:grid;grid-template-columns:160px 1fr;gap:8px 16px;font-size:0.9rem;margin-bottom:16px;">
        <span style="color:#666;font-weight:500;">Bot Token</span>
        <span><code><%= @bot_token_masked %></code></span>

        <span style="color:#666;font-weight:500;">Expected URL</span>
        <span><code><%= @expected_webhook_url %></code></span>

        <%= if @webhook_info do %>
          <span style="color:#666;font-weight:500;">Current URL</span>
          <span>
            <code><%= @webhook_info.url %></code>
            <%= if @webhook_info.url == @expected_webhook_url do %>
              <span style="color:#16a34a;margin-left:8px;">&#10003; Match</span>
            <% else %>
              <span style="color:#dc2626;margin-left:8px;">&#10007; Mismatch</span>
            <% end %>
          </span>

          <span style="color:#666;font-weight:500;">Pending Updates</span>
          <span><%= @webhook_info.pending_update_count %></span>

          <%= if @webhook_info.last_error_message do %>
            <span style="color:#666;font-weight:500;">Last Error</span>
            <span style="color:#dc2626;"><%= @webhook_info.last_error_message %></span>
          <% end %>
        <% else %>
          <span style="color:#666;font-weight:500;">Status</span>
          <span style="color:#9ca3af;">Unable to fetch webhook info</span>
        <% end %>
      </div>

      <div style="display:flex;gap:8px;flex-wrap:wrap;align-items:center;">
        <button phx-click="refresh_webhook" style="padding:8px 16px;background:#f3f4f6;border:1px solid #d1d5db;border-radius:6px;cursor:pointer;font-size:0.85rem;">
          Refresh
        </button>
        <%= if @confirm_fix do %>
          <span style="font-size:0.85rem;color:#666;">
            Set webhook to <code><%= @expected_webhook_url %></code> ?
          </span>
          <button phx-click="confirm_fix_webhook" style="padding:8px 16px;background:#2563eb;color:#fff;border:none;border-radius:6px;cursor:pointer;font-size:0.85rem;">
            Confirm
          </button>
          <button phx-click="cancel_fix_webhook" style="padding:8px 16px;background:#f3f4f6;border:1px solid #d1d5db;border-radius:6px;cursor:pointer;font-size:0.85rem;">
            Cancel
          </button>
        <% else %>
          <button phx-click="fix_webhook" style="padding:8px 16px;background:#2563eb;color:#fff;border:none;border-radius:6px;cursor:pointer;font-size:0.85rem;">
            Fix Webhook
          </button>
        <% end %>
      </div>
    </div>

    <%!-- Admin Accounts Section --%>
    <div style="background:#fff;padding:20px 24px;border-radius:8px;box-shadow:0 1px 3px rgba(0,0,0,0.06);margin-bottom:24px;">
      <h2 style="margin:0 0 16px;font-size:1.1rem;font-weight:600;">Admin Accounts</h2>
      <table style="width:100%;border-collapse:collapse;">
        <thead>
          <tr>
            <th style="text-align:left;padding:8px 16px;font-size:0.8rem;font-weight:500;color:#666;border-bottom:1px solid #eee;text-transform:uppercase;">Email</th>
            <th style="text-align:left;padding:8px 16px;font-size:0.8rem;font-weight:500;color:#666;border-bottom:1px solid #eee;text-transform:uppercase;">Created</th>
          </tr>
        </thead>
        <tbody>
          <tr :for={admin <- @admins} style="border-bottom:1px solid #f0f0f0;">
            <td style="padding:10px 16px;font-size:0.9rem;"><%= admin.email %></td>
            <td style="padding:10px 16px;font-size:0.9rem;color:#666;"><%= admin.inserted_at %></td>
          </tr>
        </tbody>
      </table>
      <%= if @admins == [] do %>
        <p style="color:#9ca3af;font-size:0.9rem;padding:8px 0;">No admin accounts found.</p>
      <% end %>
    </div>
    """
  end
end
