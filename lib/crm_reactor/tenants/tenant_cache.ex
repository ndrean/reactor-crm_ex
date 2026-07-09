defmodule CrmReactor.Tenants.TenantCache do
  @moduledoc """
  ETS-backed cache for user_identifier → tenant lookups.

  Eliminates the `user_mappings JOIN tenants` query on every request.
  Reads bypass the GenServer via direct ETS lookup.
  Call `reload/0` after provisioning or toggling tenants.
  """
  use GenServer

  import Ecto.Query

  alias CrmReactor.Repo
  alias CrmReactor.Tenants.{Tenant, UserMapping}

  require Logger

  @table :tenant_cache

  # ── Public API ────────────────────────────────────────────────────────────

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Looks up the tenant for a user identifier. Returns `{:ok, tenant_map}` or
  `{:error, :unknown_user}`. Reads directly from ETS — no GenServer roundtrip.
  """
  def lookup(user_id) do
    case :ets.lookup(@table, user_id) do
      [{^user_id, tenant}] -> {:ok, tenant}
      [] -> {:error, :unknown_user}
    end
  end

  @doc "Reloads all mappings from the database (synchronous)."
  def reload do
    GenServer.call(__MODULE__, :reload)
  end

  # ── GenServer callbacks ───────────────────────────────────────────────────

  @impl true
  def init(_opts) do
    table = :ets.new(@table, [:named_table, :set, :protected, {:read_concurrency, true}])
    load(table)
    {:ok, %{table: table}}
  end

  @impl true
  def handle_call(:reload, _from, state) do
    try do
      load(state.table)
    rescue
      e -> Logger.debug("#{__MODULE__} reload skipped: #{inspect(e)}")
    catch
      :exit, _ -> Logger.debug("#{__MODULE__} reload skipped: DB connection unavailable")
    end

    {:reply, :ok, state}
  end

  # ── Private ───────────────────────────────────────────────────────────────

  defp load(table) do
    entries =
      from(m in UserMapping,
        join: t in Tenant,
        on: t.tenant_id == m.tenant_id,
        where: t.is_active == true,
        select:
          {m.user_identifier,
           %{
             tenant_id: t.tenant_id,
             schema_name: t.schema_name,
             company_name: t.company_name,
             admin_email: t.admin_email,
             webhook_url: t.webhook_url,
             webhook_secret: t.webhook_secret
           }}
      )
      |> Repo.all()

    :ets.delete_all_objects(table)
    :ets.insert(table, entries)
  end
end
