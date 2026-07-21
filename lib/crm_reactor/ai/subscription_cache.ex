defmodule CrmReactor.AI.SubscriptionCache do
  @moduledoc """
  ETS-backed cache for per-tenant workflow subscription overrides.

  Default is enabled — only rows that deviate from the default need to exist in the DB.
  Reads bypass the GenServer via direct ETS lookup.
  Call `set/3` to persist a change to DB and update ETS immediately.
  """
  use GenServer

  alias CrmReactor.Repo
  alias CrmReactor.Tenants.TenantWorkflowOverride

  import Ecto.Query

  @table :subscription_cache

  # ── Public API ────────────────────────────────────────────────────────────

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc "Returns true if the workflow is enabled for the tenant. Unknown tenants/workflows default to true."
  def enabled?(tenant_id, workflow_name) do
    case :ets.lookup(@table, {tenant_id, workflow_name}) do
      [{{^tenant_id, ^workflow_name}, enabled}] -> enabled
      [] -> true
    end
  end

  @doc """
  Persists an override to the DB (upsert) and updates the ETS cache immediately.
  Safe to call from Stripe webhook handlers or admin endpoints.
  """
  def set(tenant_id, workflow_name, enabled) do
    GenServer.call(__MODULE__, {:set, tenant_id, workflow_name, enabled})
  end

  @doc "Reloads all overrides from the database asynchronously (cast — does not block caller)."
  def reload do
    GenServer.cast(__MODULE__, :reload)
  end

  @doc """
  Reloads from DB without sending a NOTIFY (used by CacheListener to avoid loops).
  Note: reload/0 also doesn't notify — only set/3 does. This exists for API
  symmetry with TenantCache.reload_local/0.
  """
  def reload_local do
    GenServer.cast(__MODULE__, :reload)
  end

  # ── GenServer callbacks ───────────────────────────────────────────────────

  @impl true
  def init(_opts) do
    table = :ets.new(@table, [:named_table, :set, :protected, {:read_concurrency, true}])
    load(table)
    {:ok, %{table: table}}
  end

  @impl true
  def handle_call({:set, tenant_id, workflow_name, enabled}, _from, state) do
    result =
      Repo.insert(
        %TenantWorkflowOverride{
          tenant_id: tenant_id,
          workflow_name: workflow_name,
          enabled: enabled
        },
        on_conflict: [set: [enabled: enabled]],
        conflict_target: [:tenant_id, :workflow_name],
        prefix: "global_registry"
      )

    case result do
      {:ok, _} ->
        :ets.insert(state.table, {{tenant_id, workflow_name}, enabled})
        notify_replicas()
        {:reply, :ok, state}

      {:error, _} = err ->
        {:reply, err, state}
    end
  end

  @impl true
  def handle_cast(:reload, state) do
    load(state.table)
    {:noreply, state}
  end

  defp notify_replicas do
    Repo.query("SELECT pg_notify('cache_reload', 'subscription_cache')")
  rescue
    _ -> :ok
  end

  # ── Private ───────────────────────────────────────────────────────────────

  defp load(table) do
    overrides =
      Repo.all(
        from(o in TenantWorkflowOverride, select: {o.tenant_id, o.workflow_name, o.enabled})
      )

    new_entries =
      Map.new(overrides, fn {tenant_id, workflow_name, enabled} ->
        {{tenant_id, workflow_name}, enabled}
      end)

    # Remove stale keys that no longer exist in DB
    old_keys = :ets.tab2list(table) |> Enum.map(fn {key, _} -> key end) |> MapSet.new()
    new_keys = MapSet.new(Map.keys(new_entries))
    stale_keys = MapSet.difference(old_keys, new_keys)
    Enum.each(stale_keys, &:ets.delete(table, &1))

    # Insert/update all current entries (atomic per key)
    :ets.insert(table, Map.to_list(new_entries))
  end
end
