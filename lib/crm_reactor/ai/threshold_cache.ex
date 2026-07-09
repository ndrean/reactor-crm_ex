defmodule CrmReactor.AI.ThresholdCache do
  @moduledoc """
  ETS-backed cache for per-workflow confidence thresholds.

  Reads bypass the GenServer via direct ETS lookup.
  Call `reload/0` after ThresholdCalibrationWorker updates thresholds.
  """
  use GenServer

  alias CrmReactor.AI.RoutingThreshold
  alias CrmReactor.Repo

  require Logger

  @table :routing_thresholds_cache
  @default_threshold 0.70

  # ── Public API ────────────────────────────────────────────────────────────

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc "Returns the confidence threshold for the given workflow. Defaults to 0.70 if unknown."
  def get(workflow_name) do
    case :ets.lookup(@table, workflow_name) do
      [{^workflow_name, threshold}] -> threshold
      [] -> @default_threshold
    end
  end

  @doc "Reloads thresholds from the database. Blocks until the load completes."
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
    # Query first — only wipe ETS if the query succeeds, so stale data survives failures
    thresholds = Repo.all(RoutingThreshold)
    :ets.delete_all_objects(table)

    Enum.each(thresholds, fn row ->
      :ets.insert(table, {row.workflow_name, row.threshold})
    end)
  end
end
