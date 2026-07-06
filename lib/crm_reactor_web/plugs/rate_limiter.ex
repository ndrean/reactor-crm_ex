defmodule CrmReactorWeb.Plugs.RateLimiter do
  @moduledoc "Rate limiter plug using Hammer. 30 requests/minute per user_id."
  import Plug.Conn

  @max_requests 30
  @window_ms 60_000

  def init(opts), do: opts

  def call(conn, _opts) do
    user_id = conn.params["user_id"] || conn.remote_ip |> :inet.ntoa() |> to_string()

    case Hammer.check_rate("crm:#{user_id}", @window_ms, @max_requests) do
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
