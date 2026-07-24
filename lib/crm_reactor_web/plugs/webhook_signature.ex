defmodule CrmReactorWeb.Plugs.WebhookSignature do
  @moduledoc """
  Verifies HMAC-SHA256 webhook signatures.

  The sender computes `sha256=HMAC-SHA256(secret, raw_body)` and sends it
  in the `x-webhook-signature` header. The secret never travels over the wire.

  Requires `CacheRawBody` to have cached the raw body in `conn.private.raw_body`.
  """

  import Plug.Conn
  @behaviour Plug

  @impl true
  def init(opts) do
    %{
      secret_key: Keyword.fetch!(opts, :secret_key),
      header: Keyword.get(opts, :header, "x-webhook-signature")
    }
  end

  @impl true
  def call(conn, %{secret_key: secret_key, header: header}) do
    secret = Application.get_env(:crm_reactor, secret_key)

    with raw_body when is_binary(raw_body) <- conn.private[:raw_body],
         [signature_header] <- get_req_header(conn, header),
         received_hash when is_binary(received_hash) <- extract_hash(signature_header),
         true <- is_binary(secret) and byte_size(secret) > 0 do
      computed =
        :crypto.mac(:hmac, :sha256, secret, raw_body)
        |> Base.encode16(case: :lower)

      if Plug.Crypto.secure_compare(computed, received_hash) do
        conn
      else
        conn |> send_resp(401, ~s({"error":"Invalid signature"})) |> halt()
      end
    else
      _ ->
        conn |> send_resp(401, ~s({"error":"Missing or invalid signature"})) |> halt()
    end
  end

  defp extract_hash("sha256=" <> hash) when byte_size(hash) == 64, do: hash
  defp extract_hash(_), do: nil
end
