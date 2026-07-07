defmodule CrmReactor.AI.RegistryCache do
  @moduledoc """
  ETS-backed cache for the global module registry.

  Reads bypass the GenServer via direct ETS lookup — no serialization bottleneck.
  Call `reload/0` after running migrations to pick up registry changes at runtime.
  """
  use GenServer

  alias CrmReactor.AI.SubscriptionCache
  alias CrmReactor.Repo
  alias CrmReactor.Tenants.ModuleRegistry

  @table :module_registry_cache

  # ── Public API ────────────────────────────────────────────────────────────

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc "Returns all module registry entries. Reads directly from ETS — no GenServer roundtrip."
  def all do
    case :ets.lookup(@table, :entries) do
      [{:entries, entries}] -> entries
      [] -> []
    end
  end

  @doc "Returns registry entries enabled for the given tenant. Unknown tenants get all entries."
  def for_tenant(tenant_id) do
    Enum.filter(all(), &SubscriptionCache.enabled?(tenant_id, &1.workflow_name))
  end

  @doc "Reloads entries from the database asynchronously (cast — does not block caller)."
  def reload do
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
  def handle_cast(:reload, state) do
    load(state.table)
    {:noreply, state}
  end

  # ── Private ───────────────────────────────────────────────────────────────

  defp load(table) do
    entries = Repo.all(ModuleRegistry)
    :ets.insert(table, {:entries, entries})
  end
end
