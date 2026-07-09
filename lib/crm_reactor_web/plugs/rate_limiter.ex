defmodule CrmReactorWeb.Plugs.RateLimiter do
  @moduledoc "Rate limiter plug using Hammer. 30 requests/minute per user_id."
  import Plug.Conn

  @max_requests 30
  @window_ms 60_000

  def init(opts), do: opts

  def call(conn, _opts) do
    ip = conn.remote_ip |> :inet.ntoa() |> to_string()
    user_id = conn.params["user_id"]
    key = if user_id, do: "crm:#{user_id}:#{ip}", else: "crm_ip:#{ip}"

    case Hammer.check_rate(key, @window_ms, @max_requests) do
      {:allow, _count} ->
        conn

      {:deny, _limit} ->
        conn
        |> put_status(429)
        |> Phoenix.Controller.json(%{error: "Rate limit exceeded. Try again later."})
        |> halt()
    end
  end
end
