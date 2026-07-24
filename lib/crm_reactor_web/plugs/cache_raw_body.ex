defmodule CrmReactorWeb.Plugs.CacheRawBody do
  @moduledoc """
  Custom body reader for `Plug.Parsers` that caches the raw body in
  `conn.private[:raw_body]` for webhook paths so it can be used for
  HMAC signature verification after parsing.

  Only caches for paths starting with "/webhook/email".
  Other paths use the default `Plug.Conn.read_body/2` with zero overhead.

  ## Usage in endpoint.ex

      plug Plug.Parsers,
        body_reader: {CrmReactorWeb.Plugs.CacheRawBody, :read_body, []},
        ...
  """

  @cached_prefix "/webhook/email"

  def read_body(%Plug.Conn{request_path: path} = conn, opts)
      when is_binary(path) do
    if String.starts_with?(path, @cached_prefix) do
      case Plug.Conn.read_body(conn, opts) do
        {:ok, body, conn} ->
          cached = (conn.private[:raw_body] || "") <> body
          {:ok, body, Plug.Conn.put_private(conn, :raw_body, cached)}

        {:more, body, conn} ->
          cached = (conn.private[:raw_body] || "") <> body
          {:more, body, Plug.Conn.put_private(conn, :raw_body, cached)}

        {:error, reason} ->
          {:error, reason}
      end
    else
      Plug.Conn.read_body(conn, opts)
    end
  end
end
