defmodule CrmReactorWeb.AdminLive.TelegramSetup do
  use CrmReactorWeb, :live_view

  import CrmReactorWeb.AdminComponents

  alias CrmReactor.Tenants.Provisioner

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, page_title: "Telegram Setup", result: nil)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.flash_group flash={@flash} />
    <h1>Telegram Setup</h1>
    <p style="color:#666;margin-bottom:20px;font-size:0.9rem;">
      Provision a new tenant with a Telegram user in one step.
    </p>

    <.admin_form id="telegram-setup-form" phx_submit="setup">
      <div>
        <label style="display:block;font-size:0.8rem;font-weight:500;margin-bottom:4px;">Tenant ID</label>
        <input type="text" name="tenant_id" required placeholder="acme_corp" style="padding:8px 12px;border:1px solid #ddd;border-radius:6px;font-size:0.875rem;" />
      </div>
      <div>
        <label style="display:block;font-size:0.8rem;font-weight:500;margin-bottom:4px;">Company Name</label>
        <input type="text" name="company_name" required placeholder="Acme Corp" style="padding:8px 12px;border:1px solid #ddd;border-radius:6px;font-size:0.875rem;" />
      </div>
      <div>
        <label style="display:block;font-size:0.8rem;font-weight:500;margin-bottom:4px;">Telegram Chat ID</label>
        <input type="text" name="telegram_chat_id" required placeholder="123456789" style="padding:8px 12px;border:1px solid #ddd;border-radius:6px;font-size:0.875rem;" />
      </div>
      <div>
        <label style="display:block;font-size:0.8rem;font-weight:500;margin-bottom:4px;">User Email</label>
        <input type="email" name="user_email" required placeholder="user@acme.com" style="padding:8px 12px;border:1px solid #ddd;border-radius:6px;font-size:0.875rem;" />
      </div>
      <button type="submit" style="padding:8px 20px;background:#4f46e5;color:#fff;border:none;border-radius:6px;font-size:0.875rem;cursor:pointer;">Provision & Link</button>
    </.admin_form>

    <%= if @result do %>
      <div style="background:#fff;padding:20px 24px;border-radius:8px;box-shadow:0 1px 3px rgba(0,0,0,0.06);">
        <h3 style="font-size:1rem;margin-bottom:12px;color:#065f46;">Setup Complete</h3>
        <dl style="font-size:0.875rem;line-height:1.8;">
          <dt style="font-weight:500;display:inline;">Tenant ID:</dt>
          <dd style="display:inline;margin-left:8px;font-family:monospace;"><%= @result.tenant_id %></dd><br/>
          <dt style="font-weight:500;display:inline;">Schema:</dt>
          <dd style="display:inline;margin-left:8px;font-family:monospace;"><%= @result.schema_name %></dd><br/>
          <dt style="font-weight:500;display:inline;">Chat ID:</dt>
          <dd style="display:inline;margin-left:8px;font-family:monospace;"><%= @result.chat_id %></dd>
        </dl>
        <p style="margin-top:16px;font-size:0.85rem;color:#666;">
          The user can now send messages to your Telegram bot. Messages from chat ID <code><%= @result.chat_id %></code> will be routed to tenant <code><%= @result.tenant_id %></code>.
        </p>
      </div>
    <% end %>
    """
  end

  @impl true
  def handle_event(
        "setup",
        %{
          "tenant_id" => tid,
          "company_name" => name,
          "telegram_chat_id" => chat_id,
          "user_email" => user_email
        },
        socket
      )
      when user_email != "" do
    admin_email = socket.assigns.current_account.email
    opts = [admin_email: admin_email, user_email: user_email]

    case Provisioner.provision(tid, name, chat_id, opts) do
      {:ok, tenant} ->
        result = %{
          tenant_id: tenant.tenant_id,
          schema_name: tenant.schema_name,
          chat_id: chat_id
        }

        {:noreply,
         socket
         |> assign(:result, result)
         |> put_flash(:info, "Tenant #{tid} provisioned with Telegram user #{chat_id}")}

      {:error, :invalid_tenant_id} ->
        {:noreply,
         put_flash(
           socket,
           :error,
           "Invalid tenant ID (lowercase alphanumeric + underscores only)"
         )}

      {:error, changeset} ->
        msg =
          Ecto.Changeset.traverse_errors(changeset, fn {msg, _} -> msg end)
          |> Enum.map_join(", ", fn {k, v} -> "#{k}: #{Enum.join(v, ", ")}" end)

        {:noreply, put_flash(socket, :error, msg)}
    end
  end
end
