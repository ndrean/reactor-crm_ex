defmodule CrmReactor.Tenants.TenantCache do
  @moduledoc """
  ETS-backed cache for user identifier → tenant lookups.

  Stores both email and telegram_id keys pointing to the same tenant map.
  Reads bypass the GenServer via direct ETS lookup.
  Call `reload/0` after provisioning or toggling tenants.
  """
  use GenServer

  import Ecto.Query

  alias CrmReactor.Repo
  alias CrmReactor.Tenants.{Tenant, UserMapping}

  require Logger

  @table :tenant_cache
  @canonical_table :tenant_canonical_ids

  # ── Public API ────────────────────────────────────────────────────────────

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Looks up the tenant for a user identifier (email or telegram_id).
  Returns `{:ok, tenant_map}` or `{:error, :unknown_user}`.
  Reads directly from ETS — no GenServer roundtrip.
  """
  def lookup(user_id) do
    case :ets.lookup(@table, user_id) do
      [{^user_id, %{status: "suspended"}}] -> {:error, :suspended}
      [{^user_id, tenant}] -> {:ok, tenant}
      [] -> {:error, :unknown_user}
    end
  end

  @doc """
  Resolves any identifier (email or telegram_id) to the canonical email.
  Returns the email if found, or the original identifier if not.
  """
  def resolve_canonical_id(identifier) do
    case :ets.lookup(@canonical_table, identifier) do
      [{^identifier, email}] -> email
      [] -> identifier
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

    canonical =
      :ets.new(@canonical_table, [:named_table, :set, :protected, {:read_concurrency, true}])

    try do
      load(table, canonical)
    rescue
      e -> Logger.warning("#{__MODULE__} initial load failed (pending migration?): #{inspect(e)}")
    catch
      :exit, _ -> Logger.warning("#{__MODULE__} initial load failed: DB unavailable")
    end

    {:ok, %{table: table, canonical: canonical}}
  end

  @impl true
  def handle_call(:reload, _from, state) do
    try do
      load(state.table, state.canonical)
    rescue
      e -> Logger.debug("#{__MODULE__} reload skipped: #{inspect(e)}")
    catch
      :exit, _ -> Logger.debug("#{__MODULE__} reload skipped: DB connection unavailable")
    end

    {:reply, :ok, state}
  end

  # ── Private ───────────────────────────────────────────────────────────────

  defp load(table, canonical) do
    rows =
      from(m in UserMapping,
        join: t in Tenant,
        on: t.tenant_id == m.tenant_id,
        where: t.is_active == true,
        select:
          {m.email, m.telegram_id, m.status,
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

    entries =
      Enum.flat_map(rows, fn {email, telegram_id, status, tenant_map} ->
        tenant_with_status = Map.put(tenant_map, :status, status || "active")

        if telegram_id,
          do: [{email, tenant_with_status}, {telegram_id, tenant_with_status}],
          else: [{email, tenant_with_status}]
      end)

    # Canonical ID table: maps any identifier → email
    canonical_entries =
      Enum.flat_map(rows, fn {email, telegram_id, _status, _tenant_map} ->
        if telegram_id,
          do: [{email, email}, {telegram_id, email}],
          else: [{email, email}]
      end)

    :ets.delete_all_objects(table)
    :ets.insert(table, entries)
    :ets.delete_all_objects(canonical)
    :ets.insert(canonical, canonical_entries)
  end
end
