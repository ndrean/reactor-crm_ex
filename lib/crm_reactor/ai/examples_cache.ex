defmodule CrmReactor.AI.ExamplesCache do
  @moduledoc """
  ETS-backed cache for workflow example phrases used in embedding-based routing.

  Reads bypass the GenServer via direct ETS lookup — no serialization bottleneck.
  Call `reload/0` after running `mix crm.embed_examples` to pick up new examples.
  """
  use GenServer

  alias CrmReactor.Repo
  alias CrmReactor.Tenants.RegistryExample

  require Logger

  @table :routing_examples

  # ── Public API ────────────────────────────────────────────────────────────

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc "Returns all example entries. Reads directly from ETS — no GenServer roundtrip."
  def all do
    case :ets.lookup(@table, :entries) do
      [{:entries, entries}] -> entries
      [] -> []
    end
  end

  @doc "Reloads entries from the database. Blocks until the load completes."
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
    entries = Repo.all(RegistryExample)
    :ets.insert(table, {:entries, entries})
  end
end
