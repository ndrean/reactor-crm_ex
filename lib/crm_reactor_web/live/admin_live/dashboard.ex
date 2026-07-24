defmodule CrmReactorWeb.AdminLive.Dashboard do
  use CrmReactorWeb, :live_view

  import CrmReactorWeb.AdminComponents
  import Ecto.Query

  alias CrmReactor.Repo
  alias CrmReactor.Tenants.{Tenant, UserMapping}

  @page_size 50

  @impl true
  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(
        page_title: "Dashboard",
        tenant_count: 0,
        active_tenants: 0,
        user_count: 0,
        log_count: 0,
        tenants: [],
        filter_tenant: nil,
        filter_status: nil,
        has_more: false,
        cursor: nil
      )
      |> stream(:logs, [])

    if connected?(socket) do
      tenant_count = Repo.aggregate(Tenant, :count, :id)
      user_count = Repo.aggregate(UserMapping, :count, :id)
      active_tenants = Repo.aggregate(from(t in Tenant, where: t.is_active == true), :count, :id)
      tenants = Repo.all(from(t in Tenant, select: t.tenant_id, order_by: t.tenant_id))
      default_tenant = List.first(tenants)

      {logs, has_more} = load_logs(default_tenant, nil, nil)
      cursor = last_cursor(logs)

      {:ok,
       socket
       |> assign(
         tenant_count: tenant_count,
         active_tenants: active_tenants,
         user_count: user_count,
         tenants: tenants,
         filter_tenant: default_tenant,
         log_count: length(logs),
         has_more: has_more,
         cursor: cursor
       )
       |> stream(:logs, logs, reset: true)}
    else
      {:ok, socket}
    end
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
        <div style="font-size:0.8rem;color:#666;text-transform:uppercase;letter-spacing:0.04em;">Recent Requests (7d)</div>
        <div style="font-size:2rem;font-weight:600;margin-top:4px;"><%= if @has_more, do: "50+", else: @log_count %></div>
      </div>
    </div>

    <h2 style="font-size:1.1rem;margin-bottom:12px;">Recent Activity</h2>

    <form phx-change="filter" style="display:flex;gap:12px;margin-bottom:20px;align-items:end;">
      <div>
        <label style="display:block;font-size:0.8rem;font-weight:500;margin-bottom:4px;">Tenant</label>
        <select name="tenant" style="padding:8px 12px;border:1px solid #ddd;border-radius:6px;font-size:0.875rem;">
          <option value="">All tenants</option>
          <option :for={tid <- @tenants} value={tid} selected={@filter_tenant == tid}><%= tid %></option>
        </select>
      </div>
      <div>
        <label style="display:block;font-size:0.8rem;font-weight:500;margin-bottom:4px;">Status</label>
        <select name="status" style="padding:8px 12px;border:1px solid #ddd;border-radius:6px;font-size:0.875rem;">
          <option value="">All</option>
          <option :for={s <- ["processing", "completed", "pending", "error"]} value={s} selected={@filter_status == s}><%= s %></option>
        </select>
      </div>
    </form>

    <.admin_table id="logs" rows={@streams.logs} cols={["Time", "Tenant", "User", "Input", "Module", "Action", "Status", "Output"]}>
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

    <div :if={@has_more} style="text-align:center;margin-top:16px;">
      <button phx-click="load_more" style="padding:8px 24px;border:1px solid #ddd;border-radius:6px;background:#fff;cursor:pointer;font-size:0.875rem;">
        Load more
      </button>
    </div>
    """
  end

  # ── Events ──────────────────────────────────────────────────────────────

  @impl true
  def handle_event("filter", params, socket) do
    tenant =
      case params["tenant"] do
        t when t in [nil, ""] -> nil
        t -> if t in socket.assigns.tenants, do: t
      end

    status =
      case params["status"] do
        s when s in [nil, ""] -> nil
        s -> if s in ~w(processing completed pending error), do: s
      end

    {logs, has_more} = load_logs(tenant, status, nil)
    cursor = last_cursor(logs)

    {:noreply,
     socket
     |> assign(filter_tenant: tenant, filter_status: status, has_more: has_more, cursor: cursor)
     |> stream(:logs, logs, reset: true)}
  end

  def handle_event("load_more", _params, socket) do
    %{filter_tenant: tenant, filter_status: status, cursor: cursor} = socket.assigns

    {logs, has_more} = load_logs(tenant, status, cursor)
    new_cursor = last_cursor(logs) || cursor

    {:noreply,
     socket
     |> assign(has_more: has_more, cursor: new_cursor)
     |> stream(:logs, logs)}
  end

  # ── Data loading ────────────────────────────────────────────────────────

  defp last_cursor([]), do: nil

  defp last_cursor(logs) do
    last = List.last(logs)
    {last.logged_at, last.raw_id}
  end

  defp load_logs(tenant_filter, status_filter, cursor) do
    valid_schemas = Repo.all(from(t in Tenant, select: t.schema_name))

    schemas =
      if tenant_filter do
        candidate = "customer_#{tenant_filter}"
        if candidate in valid_schemas, do: [candidate], else: []
      else
        valid_schemas
      end

    case schemas do
      [] ->
        {[], false}

      _ ->
        {conditions, params, _idx} = build_conditions(status_filter, cursor, _start_idx = 2)

        where_clause = " WHERE #{Enum.join(conditions, " AND ")}"

        union_sql =
          schemas
          |> Enum.map_join(" UNION ALL ", fn schema ->
            safe = safe_schema(schema)

            "SELECT id, triggered_by, raw_input, module, action, status, output, logged_at, '#{safe}' AS schema_name FROM #{safe}.execution_logs#{where_clause}"
          end)

        sql =
          "SELECT * FROM (#{union_sql}) AS combined ORDER BY logged_at DESC NULLS LAST, id DESC LIMIT $1"

        query_params = [@page_size + 1] ++ params

        case Repo.query(sql, query_params) do
          {:ok, %{rows: rows, columns: columns}} ->
            has_more = length(rows) > @page_size
            rows = Enum.take(rows, @page_size)
            {parse_log_rows(rows, columns), has_more}

          _ ->
            {[], false}
        end
    end
  end

  defp build_conditions(status_filter, cursor, idx) do
    conditions = ["logged_at > NOW() - INTERVAL '7 days'"]
    params = []

    {conditions, params, idx} =
      if status_filter do
        {conditions ++ ["status = $#{idx}"], params ++ [status_filter], idx + 1}
      else
        {conditions, params, idx}
      end

    {conditions, params, idx} =
      case cursor do
        {logged_at, id} ->
          condition = "(logged_at, id) < ($#{idx}, $#{idx + 1})"
          {conditions ++ [condition], params ++ [logged_at, id], idx + 2}

        nil ->
          {conditions, params, idx}
      end

    {conditions, params, idx}
  end

  # ── Parsing ─────────────────────────────────────────────────────────────

  @log_columns %{
    "id" => :id,
    "triggered_by" => :triggered_by,
    "raw_input" => :raw_input,
    "module" => :module,
    "action" => :action,
    "status" => :status,
    "output" => :output,
    "logged_at" => :logged_at,
    "schema_name" => :schema_name
  }

  defp parse_log_rows(rows, columns) do
    columns = Enum.map(columns, &Map.fetch!(@log_columns, &1))

    Enum.map(rows, fn row ->
      log = Enum.zip(columns, row) |> Map.new()

      log
      |> Map.put(:raw_id, log.id)
      |> Map.put(:id, "#{log.schema_name}-#{log.id}")
      |> Map.put(:schema, log.schema_name)
    end)
  end

  # ── Helpers ─────────────────────────────────────────────────────────────

  defp safe_schema(name) do
    if Regex.match?(~r/^customer_[a-z0-9_]+$/, name),
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
