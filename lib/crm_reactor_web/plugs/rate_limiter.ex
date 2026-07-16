defmodule CrmReactorWeb.Plugs.RateLimiter do
  @moduledoc "Rate limiter plug using Hammer. Configurable limits via plug options."
  import Plug.Conn

  @default_max 30
  @default_window_ms 60_000

  def init(opts), do: opts

  def call(conn, opts) do
    max = Keyword.get(opts, :max, @default_max)
    window = Keyword.get(opts, :window_ms, @default_window_ms)
    prefix = Keyword.get(opts, :prefix, "crm")

    ip = conn.remote_ip |> :inet.ntoa() |> to_string()
    user_id = conn.params["user_id"]
    key = if user_id, do: "#{prefix}:#{user_id}:#{ip}", else: "#{prefix}_ip:#{ip}"

    case Hammer.check_rate(key, window, max) do
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
