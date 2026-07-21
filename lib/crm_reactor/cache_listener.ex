defmodule CrmReactor.CacheListener do
  @moduledoc """
  Listens for Postgres NOTIFY events on the "cache_reload" channel
  and triggers ETS cache reloads on the local node.

  This enables cross-replica cache invalidation when running multiple
  app instances behind a load balancer — all sharing the same Postgres.
  """
  use GenServer

  require Logger

  alias CrmReactor.AI.SubscriptionCache
  alias CrmReactor.Tenants.TenantCache

  @channel "cache_reload"
  @retry_interval :timer.seconds(5)

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(opts) do
    state = %{conn: nil, opts: opts}
    send(self(), :connect)
    {:ok, state}
  end

  @impl true
  def handle_info(:connect, state) do
    repo_config = state.opts[:repo_config] || CrmReactor.Repo.config()

    conn_opts =
      repo_config
      |> Keyword.take([:hostname, :port, :username, :password, :database, :socket_dir])
      |> Keyword.put(:auto_reconnect, true)

    case Postgrex.Notifications.start_link(conn_opts) do
      {:ok, pid} ->
        Postgrex.Notifications.listen(pid, @channel)
        Logger.info("CacheListener: connected and listening on #{@channel}")
        {:noreply, %{state | conn: pid}}

      {:error, reason} ->
        Logger.warning(
          "CacheListener: connect failed (#{inspect(reason)}), retrying in #{div(@retry_interval, 1000)}s"
        )

        Process.send_after(self(), :connect, @retry_interval)
        {:noreply, %{state | conn: nil}}
    end
  end

  def handle_info({:notification, _conn, _ref, @channel, "tenant_cache"}, state) do
    Logger.debug("CacheListener: reloading TenantCache")
    TenantCache.reload_local()
    {:noreply, state}
  end

  def handle_info({:notification, _conn, _ref, @channel, "subscription_cache"}, state) do
    Logger.debug("CacheListener: reloading SubscriptionCache")
    SubscriptionCache.reload_local()
    {:noreply, state}
  end

  def handle_info({:notification, _conn, _ref, @channel, payload}, state) do
    Logger.debug("CacheListener: unknown payload #{inspect(payload)}")
    {:noreply, state}
  end

  def handle_info(_msg, state) do
    {:noreply, state}
  end
end
