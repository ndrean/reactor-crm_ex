defmodule CrmReactorWeb.AdminLive.Logs do
  use CrmReactorWeb, :live_view

  import CrmReactorWeb.AdminComponents
  import Ecto.Query

  alias CrmReactor.Repo
  alias CrmReactor.Tenants.Tenant

  @impl true
  def mount(_params, _session, socket) do
    tenants = Repo.all(from(t in Tenant, select: t.tenant_id, order_by: t.tenant_id))

    {:ok,
     socket
     |> assign(
       page_title: "Logs",
       tenants: tenants,
       filter_tenant: nil,
       filter_status: nil
     )
     |> stream(:logs, load_logs(nil, nil))}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.flash_group flash={@flash} />
    <h1>Execution Logs</h1>

    <div style="display:flex;gap:12px;margin-bottom:20px;align-items:end;">
      <div>
        <label style="display:block;font-size:0.8rem;font-weight:500;margin-bottom:4px;">Tenant</label>
        <select phx-change="filter" name="tenant" style="padding:8px 12px;border:1px solid #ddd;border-radius:6px;font-size:0.875rem;">
          <option value="">All tenants</option>
          <option :for={tid <- @tenants} value={tid} selected={@filter_tenant == tid}><%= tid %></option>
        </select>
      </div>
      <div>
        <label style="display:block;font-size:0.8rem;font-weight:500;margin-bottom:4px;">Status</label>
        <select phx-change="filter" name="status" style="padding:8px 12px;border:1px solid #ddd;border-radius:6px;font-size:0.875rem;">
          <option value="">All</option>
          <option :for={s <- ["processing", "completed", "pending", "error"]} value={s} selected={@filter_status == s}><%= s %></option>
        </select>
      </div>
    </div>

    <.admin_table rows={@streams.logs} cols={["Time", "Tenant", "User", "Input", "Module", "Action", "Status", "Output"]}>
      <:col :let={{_id, log}}>
        <td style="padding:10px 16px;font-size:0.8rem;white-space:nowrap;"><%= format_time(log.logged_at) %></td>
        <td style="padding:10px 16px;font-size:0.8rem;"><%= log.schema %></td>
        <td style="padding:10px 16px;font-size:0.8rem;"><%= log.triggered_by || "-" %></td>
        <td style="padding:10px 16px;font-size:0.8rem;max-width:200px;overflow:hidden;text-overflow:ellipsis;white-space:nowrap;" title={log.raw_input}><%= truncate(log.raw_input, 40) %></td>
        <td style="padding:10px 16px;font-size:0.8rem;"><%= log.module || "-" %></td>
        <td style="padding:10px 16px;font-size:0.8rem;"><%= log.action || "-" %></td>
        <td style="padding:10px 16px;font-size:0.8rem;">
          <span style={"display:inline-block;padding:2px 8px;border-radius:4px;font-size:0.75rem;#{status_style(log.status)}"}><%= log.status %></span>
        </td>
        <td style="padding:10px 16px;font-size:0.8rem;max-width:200px;overflow:hidden;text-overflow:ellipsis;white-space:nowrap;" title={log.output}><%= truncate(log.output, 40) %></td>
      </:col>
    </.admin_table>
    """
  end

  @impl true
  def handle_event("filter", params, socket) do
    tenant = if params["tenant"] == "", do: nil, else: params["tenant"]
    status = if params["status"] == "", do: nil, else: params["status"]

    # Preserve existing filter values when only one select changes
    tenant = tenant || socket.assigns.filter_tenant
    status = status || socket.assigns.filter_status

    # Allow clearing by re-selecting "All"
    tenant = if params["tenant"] == "", do: nil, else: tenant
    status = if params["status"] == "", do: nil, else: status

    {:noreply,
     socket
     |> assign(filter_tenant: tenant, filter_status: status)
     |> stream(:logs, load_logs(tenant, status), reset: true)}
  end

  defp load_logs(tenant_filter, status_filter) do
    schemas =
      if tenant_filter do
        ["customer_#{tenant_filter}"]
      else
        Repo.all(from(t in Tenant, select: t.schema_name))
      end

    case schemas do
      [] ->
        []

      _ ->
        {where_clause, _, _} = build_where(status_filter, 2)

        union_sql =
          schemas
          |> Enum.map_join(" UNION ALL ", fn schema ->
            safe = safe_schema(schema)

            "SELECT id, triggered_by, raw_input, module, action, status, output, logged_at, '#{safe}' AS schema_name FROM #{safe}.execution_logs#{where_clause}"
          end)

        sql =
          "SELECT * FROM (#{union_sql}) AS combined ORDER BY logged_at DESC NULLS LAST LIMIT $1"

        query_params = [50] ++ if(status_filter, do: [status_filter], else: [])

        case Repo.query(sql, query_params) do
          {:ok, %{rows: rows, columns: columns}} ->
            parse_log_rows(rows, columns)

          _ ->
            []
        end
    end
  end

  defp parse_log_rows(rows, columns) do
    columns = Enum.map(columns, &String.to_atom/1)

    Enum.map(rows, fn row ->
      log = Enum.zip(columns, row) |> Map.new()
      log |> Map.put(:id, "#{log.schema_name}-#{log.id}") |> Map.put(:schema, log.schema_name)
    end)
  end

  defp build_where(nil, _idx), do: {"", [], 2}
  defp build_where(status, idx), do: {" WHERE status = $#{idx}", [status], idx + 1}

  defp safe_schema(name) do
    if Regex.match?(~r/^[a-z_][a-z0-9_]*$/, name),
      do: name,
      else: raise("invalid schema: #{name}")
  end

  defp format_time(nil), do: "-"
  defp format_time(dt), do: Calendar.strftime(dt, "%m/%d %H:%M:%S")

  defp truncate(nil, _), do: "-"
  defp truncate(s, max) when byte_size(s) <= max, do: s
  defp truncate(s, max), do: String.slice(s, 0, max) <> "..."

  defp status_style("completed"), do: "background:#ecfdf5;color:#065f46;"
  defp status_style("processing"), do: "background:#eff6ff;color:#1e40af;"
  defp status_style("pending"), do: "background:#fffbeb;color:#92400e;"
  defp status_style("error"), do: "background:#fef2f2;color:#991b1b;"
  defp status_style(_), do: "background:#f5f5f5;color:#666;"
end
