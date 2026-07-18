defmodule CrmReactor.TestPlugServer do
  @moduledoc ~S"""
  Lightweight HTTP test server using Bandit (replaces Bypass).

  ## Usage

      {:ok, port, pid} = TestPlugServer.start(fn conn ->
        Plug.Conn.send_resp(conn, 200, "OK")
      end)

      on_exit(fn -> TestPlugServer.stop(pid) end)
  """

  def start(handler) when is_function(handler, 1) do
    ref = make_ref()
    :persistent_term.put({__MODULE__, ref}, handler)
    plug = {CrmReactor.TestPlugServer.Handler, ref: ref}
    {:ok, pid} = Bandit.start_link(plug: plug, port: 0, startup_log: false)
    {:ok, {_ip, port}} = ThousandIsland.listener_info(pid)
    # Store ref so stop/1 can erase the persistent_term entry
    :persistent_term.put({__MODULE__, :ref, pid}, ref)
    {:ok, port, pid}
  end

  def stop(pid) do
    case :persistent_term.get({__MODULE__, :ref, pid}, nil) do
      nil ->
        :ok

      ref ->
        :persistent_term.erase({__MODULE__, :ref, pid})
        :persistent_term.erase({__MODULE__, ref})
    end

    Supervisor.stop(pid, :normal)
  catch
    :exit, _ -> :ok
  end
end

defmodule CrmReactor.TestPlugServer.Handler do
  @moduledoc false
  @behaviour Plug

  @impl true
  def init(opts), do: opts

  @impl true
  def call(conn, ref: ref) do
    handler = :persistent_term.get({CrmReactor.TestPlugServer, ref})
    handler.(conn)
  end
end
