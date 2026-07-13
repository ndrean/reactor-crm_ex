defmodule CrmReactorWeb.AdminLive.Subscriptions do
  use CrmReactorWeb, :live_view

  import CrmReactorWeb.AdminComponents

  alias CrmReactor.AI.{RegistryCache, SubscriptionCache}
  alias CrmReactor.Repo
  alias CrmReactor.Tenants.Tenant

  @impl true
  def mount(_params, _session, socket) do
    tenants = Repo.all(Tenant)

    workflows =
      RegistryCache.all()
      |> Enum.map(& &1.workflow_name)
      |> Enum.uniq()
      |> Enum.sort()

    matrix =
      for t <- tenants, into: %{} do
        row =
          for wf <- workflows, into: %{} do
            {wf, SubscriptionCache.enabled?(t.tenant_id, wf)}
          end

        {t.tenant_id, row}
      end

    {:ok,
     assign(socket,
       page_title: "Subscriptions",
       tenants: tenants,
       workflows: workflows,
       matrix: matrix
     )}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.flash_group flash={@flash} />
    <h1>Workflow Subscriptions</h1>

    <table style="width:100%;border-collapse:collapse;background:#fff;border-radius:8px;overflow:hidden;box-shadow:0 1px 3px rgba(0,0,0,0.06);">
      <thead>
        <tr>
          <th style="text-align:left;padding:10px 16px;font-size:0.8rem;font-weight:500;color:#666;border-bottom:1px solid #eee;">Tenant</th>
          <th :for={wf <- @workflows} style="text-align:center;padding:10px 16px;font-size:0.8rem;font-weight:500;color:#666;border-bottom:1px solid #eee;text-transform:capitalize;">
            <%= wf %>
          </th>
        </tr>
      </thead>
      <tbody>
        <tr :for={tenant <- @tenants} style="border-bottom:1px solid #f0f0f0;">
          <td style="padding:10px 16px;font-size:0.875rem;font-weight:500;"><%= tenant.tenant_id %></td>
          <td :for={wf <- @workflows} style="text-align:center;padding:10px 16px;">
            <% enabled = @matrix[tenant.tenant_id][wf] %>
            <button
              phx-click="toggle"
              phx-value-tenant={tenant.tenant_id}
              phx-value-workflow={wf}
              phx-value-enabled={to_string(!enabled)}
              style={"padding:4px 16px;border:none;border-radius:4px;font-size:0.8rem;cursor:pointer;#{if enabled, do: "background:#ecfdf5;color:#065f46;", else: "background:#fef2f2;color:#991b1b;"}"}
            >
              <%= if enabled, do: "ON", else: "OFF" %>
            </button>
          </td>
        </tr>
      </tbody>
    </table>
    """
  end

  @impl true
  def handle_event(
        "toggle",
        %{"tenant" => tid, "workflow" => wf, "enabled" => enabled_str},
        socket
      ) do
    enabled = enabled_str == "true"

    case SubscriptionCache.set(tid, wf, enabled) do
      :ok ->
        matrix = put_in(socket.assigns.matrix, [tid, wf], enabled)

        {:noreply,
         socket
         |> assign(:matrix, matrix)
         |> put_flash(:info, "#{wf} #{if enabled, do: "enabled", else: "disabled"} for #{tid}")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to update subscription")}
    end
  end
end
