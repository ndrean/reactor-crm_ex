defmodule CrmReactorWeb.AdminLive.Dashboard do
  use CrmReactorWeb, :live_view

  import CrmReactorWeb.AdminComponents
  import Ecto.Query

  alias CrmReactor.Repo
  alias CrmReactor.Tenants.{Tenant, UserMapping}

  @impl true
  def mount(_params, _session, socket) do
    tenant_count = Repo.aggregate(Tenant, :count, :id)
    user_count = Repo.aggregate(UserMapping, :count, :id)

    active_tenants = Repo.aggregate(from(t in Tenant, where: t.is_active == true), :count, :id)

    recent_logs = load_recent_logs(10)

    {:ok,
     socket
     |> assign(
       page_title: "Dashboard",
       tenant_count: tenant_count,
       active_tenants: active_tenants,
       user_count: user_count,
       log_count: length(recent_logs)
     )
     |> stream(:recent_logs, recent_logs)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.flash_group flash={@flash} />
    <h1>Dashboard</h1>

    <div style="display:grid;grid-template-columns:repeat(3,1fr);gap:16px;margin-bottom:32px;">
      <div style="background:#fff;padding:20px 24px;border-radius:8px;box-shadow:0 1px 3px rgba(0,0,0,0.06);">
        <div style="font-size:0.8rem;color:#666;text-transform:uppercase;letter-spacing:0.04em;">Active Tenants</div>
        <div style="font-size:2rem;font-weight:600;margin-top:4px;"><%= @active_tenants %> / <%= @tenant_count %></div>
      </div>
      <div style="background:#fff;padding:20px 24px;border-radius:8px;box-shadow:0 1px 3px rgba(0,0,0,0.06);">
        <div style="font-size:0.8rem;color:#666;text-transform:uppercase;letter-spacing:0.04em;">Total Users</div>
        <div style="font-size:2rem;font-weight:600;margin-top:4px;"><%= @user_count %></div>
      </div>
      <div style="background:#fff;padding:20px 24px;border-radius:8px;box-shadow:0 1px 3px rgba(0,0,0,0.06);">
        <div style="font-size:0.8rem;color:#666;text-transform:uppercase;letter-spacing:0.04em;">Recent Requests</div>
        <div style="font-size:2rem;font-weight:600;margin-top:4px;"><%= @log_count %></div>
      </div>
    </div>

    <h2 style="font-size:1.1rem;margin-bottom:12px;">Recent Activity</h2>
    <.admin_table rows={@streams.recent_logs} cols={["Time", "Tenant", "User", "Module", "Action", "Status"]}>
      <:col :let={{_id, log}}>
        <td style="padding:10px 16px;font-size:0.875rem;"><%= format_time(log.logged_at) %></td>
        <td style="padding:10px 16px;font-size:0.875rem;"><%= log.schema %></td>
        <td style="padding:10px 16px;font-size:0.875rem;"><%= log.triggered_by || "-" %></td>
        <td style="padding:10px 16px;font-size:0.875rem;"><%= log.module || "-" %></td>
        <td style="padding:10px 16px;font-size:0.875rem;"><%= log.action || "-" %></td>
        <td style="padding:10px 16px;font-size:0.875rem;">
          <span style={"display:inline-block;padding:2px 8px;border-radius:4px;font-size:0.75rem;#{status_style(log.status)}"}><%= log.status %></span>
        </td>
      </:col>
    </.admin_table>
    """
  end

  defp load_recent_logs(limit) do
    schemas = Repo.all(from(t in Tenant, select: t.schema_name))

    case schemas do
      [] ->
        []

      _ ->
        union_sql =
          schemas
          |> Enum.map_join(" UNION ALL ", fn schema ->
            safe = safe_schema(schema)

            "SELECT id, triggered_by, module, action, status, logged_at, '#{safe}' AS schema_name FROM #{safe}.execution_logs"
          end)

        sql =
          "SELECT * FROM (#{union_sql}) AS combined ORDER BY logged_at DESC NULLS LAST LIMIT $1"

        case Repo.query(sql, [limit]) do
          {:ok, %{rows: rows, columns: columns}} ->
            parse_log_rows(rows, columns)

          _ ->
            []
        end
    end
  end

  @log_columns %{
    "id" => :id,
    "triggered_by" => :triggered_by,
    "module" => :module,
    "action" => :action,
    "status" => :status,
    "logged_at" => :logged_at,
    "schema_name" => :schema_name
  }

  defp parse_log_rows(rows, columns) do
    columns = Enum.map(columns, &Map.fetch!(@log_columns, &1))

    Enum.map(rows, fn row ->
      log = Enum.zip(columns, row) |> Map.new()
      log |> Map.put(:id, "#{log.schema_name}-#{log.id}") |> Map.put(:schema, log.schema_name)
    end)
  end

  defp safe_schema(name) do
    if Regex.match?(~r/^[a-z_][a-z0-9_]*$/, name),
      do: name,
      else: raise("invalid schema: #{name}")
  end

  defp format_time(nil), do: "-"
  defp format_time(dt), do: Calendar.strftime(dt, "%H:%M:%S")

  defp status_style("completed"), do: "background:#ecfdf5;color:#065f46;"
  defp status_style("processing"), do: "background:#eff6ff;color:#1e40af;"
  defp status_style("error"), do: "background:#fef2f2;color:#991b1b;"
  defp status_style(_), do: "background:#f5f5f5;color:#666;"
end
