defmodule CrmReactorWeb.AdminLive.Tenants do
  use CrmReactorWeb, :live_view

  import CrmReactorWeb.AdminComponents

  alias CrmReactor.Repo
  alias CrmReactor.Tenants.{Provisioner, Tenant}

  @impl true
  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(page_title: "Tenants")
      |> stream(:tenants, [])

    if connected?(socket) do
      {:ok, stream(socket, :tenants, Repo.all(Tenant), reset: true)}
    else
      {:ok, socket}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.flash_group flash={@flash} />
    <h1>Tenants</h1>

    <.admin_form id="provision-form" phx_submit="provision">
      <div>
        <label style="display:block;font-size:0.8rem;font-weight:500;margin-bottom:4px;">Tenant ID</label>
        <input type="text" name="tenant_id" required placeholder="acme_corp" style="padding:8px 12px;border:1px solid #ddd;border-radius:6px;font-size:0.875rem;" />
      </div>
      <div>
        <label style="display:block;font-size:0.8rem;font-weight:500;margin-bottom:4px;">Company Name</label>
        <input type="text" name="company_name" required placeholder="Acme Corp" style="padding:8px 12px;border:1px solid #ddd;border-radius:6px;font-size:0.875rem;" />
      </div>
      <div>
        <label style="display:inline-flex;align-items:center;gap:4px;font-size:0.8rem;font-weight:500;margin-bottom:4px;">
          Admin Email
          <span id="admin-email-tip" phx-hook="Tippy" data-tippy-content="Recipient address for data export and cost reports requested by users of this tenant." data-tippy-placement="right" style="cursor:help;color:#999;font-size:0.75rem;">&#9432;</span>
        </label>
        <input type="email" name="admin_email" placeholder="admin@acme.com" style="display:block;padding:8px 12px;border:1px solid #ddd;border-radius:6px;font-size:0.875rem;" />
      </div>
      <button type="submit" style="padding:8px 20px;background:#4f46e5;color:#fff;border:none;border-radius:6px;font-size:0.875rem;cursor:pointer;">Provision</button>
    </.admin_form>

    <.admin_table id="tenants" rows={@streams.tenants} cols={["Tenant ID", "Company", "Schema", "Active", "Webhook URL", "Actions"]}>
      <:col :let={{_id, tenant}}>
        <td style="padding:10px 16px;font-size:0.875rem;font-weight:500;"><%= tenant.tenant_id %></td>
        <td style="padding:10px 16px;font-size:0.875rem;"><%= tenant.company_name %></td>
        <td style="padding:10px 16px;font-size:0.875rem;font-family:monospace;"><%= tenant.schema_name %></td>
        <td style="padding:10px 16px;font-size:0.875rem;">
          <button
            phx-click="toggle"
            phx-value-id={tenant.tenant_id}
            phx-value-active={to_string(!tenant.is_active)}
            style={"padding:4px 12px;border:none;border-radius:4px;font-size:0.8rem;cursor:pointer;#{if tenant.is_active, do: "background:#ecfdf5;color:#065f46;", else: "background:#fef2f2;color:#991b1b;"}"}
          >
            <%= if tenant.is_active, do: "Active", else: "Inactive" %>
          </button>
        </td>
        <td style="padding:10px 16px;font-size:0.875rem;">
          <div style="display:flex;align-items:center;gap:6px;">
            <span id={"webhook-tip-#{tenant.tenant_id}"} phx-hook="Tippy" data-tippy-content="When set, workflow results (contact created, todo completed, etc.) are POSTed here as HMAC-signed JSON. Used for external integrations." data-tippy-placement="top" style="cursor:help;color:#999;font-size:0.75rem;">&#9432;</span>
            <form phx-submit="set_webhook" style="display:flex;gap:6px;">
              <input type="hidden" name="tenant_id" value={tenant.tenant_id} />
              <input type="text" name="webhook_url" value={tenant.webhook_url || ""} placeholder="https://..." style="padding:4px 8px;border:1px solid #ddd;border-radius:4px;font-size:0.8rem;width:200px;" />
              <button type="submit" style="padding:4px 10px;background:#f5f5f5;border:1px solid #ddd;border-radius:4px;font-size:0.8rem;cursor:pointer;">Set</button>
            </form>
          </div>
        </td>
        <td style="padding:10px 16px;font-size:0.875rem;">-</td>
      </:col>
    </.admin_table>
    """
  end

  @impl true
  def handle_event("provision", %{"tenant_id" => tid, "company_name" => name} = params, socket) do
    opts = if params["admin_email"] != "", do: [admin_email: params["admin_email"]], else: []

    case Provisioner.provision(tid, name, nil, opts) do
      {:ok, tenant} ->
        {:noreply,
         socket
         |> stream_insert(:tenants, tenant)
         |> put_flash(:info, "Tenant #{tid} provisioned")}

      {:error, :invalid_tenant_id} ->
        {:noreply,
         put_flash(
           socket,
           :error,
           "Invalid tenant ID (lowercase alphanumeric + underscores only)"
         )}

      {:error, changeset} ->
        {:noreply, put_flash(socket, :error, format_errors(changeset))}
    end
  end

  def handle_event("toggle", %{"id" => tid, "active" => active_str}, socket) do
    active = active_str == "true"

    case Provisioner.toggle_active(tid, active) do
      {:ok, tenant} ->
        {:noreply,
         socket
         |> stream_insert(:tenants, tenant)
         |> put_flash(:info, "Tenant #{tid} #{if active, do: "activated", else: "deactivated"}")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to toggle tenant")}
    end
  end

  def handle_event("set_webhook", %{"tenant_id" => tid, "webhook_url" => url}, socket) do
    case Provisioner.set_webhook(tid, url) do
      {:ok, tenant} ->
        {:noreply,
         socket
         |> stream_insert(:tenants, tenant)
         |> put_flash(:info, "Webhook set for #{tid}")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to set webhook")}
    end
  end

  defp format_errors(%Ecto.Changeset{} = cs) do
    Ecto.Changeset.traverse_errors(cs, fn {msg, _} -> msg end)
    |> Enum.map_join(", ", fn {k, v} -> "#{k}: #{Enum.join(v, ", ")}" end)
  end

  defp format_errors(other), do: inspect(other)
end
