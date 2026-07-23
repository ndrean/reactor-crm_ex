defmodule CrmReactorWeb.Plugs.CSP do
  import Plug.Conn

  def init(opts), do: opts

  def call(conn, _opts) do
    nonce = Base.encode64(:crypto.strong_rand_bytes(16))

    csp =
      "base-uri 'self'; " <>
        "frame-ancestors 'self'; " <>
        "default-src 'self'; " <>
        "script-src 'self' 'nonce-#{nonce}' https://unpkg.com; " <>
        "style-src 'self' 'unsafe-inline' https://unpkg.com; " <>
        "img-src 'self' data:; " <>
        "connect-src 'self' wss: https://unpkg.com; " <>
        "font-src 'self';"

    conn
    |> put_resp_header("content-security-policy", csp)
    |> put_resp_header("x-robots-tag", "noindex, nofollow")
    |> put_resp_header("cache-control", "private")
    |> assign(:csp_nonce, nonce)
  end
end
