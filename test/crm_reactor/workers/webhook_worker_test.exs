defmodule CrmReactor.Workers.WebhookWorkerTest do
  use CrmReactor.DataCase
  use Oban.Testing, repo: CrmReactor.Repo

  alias CrmReactor.Workers.WebhookWorker

  setup do
    bypass = Bypass.open()
    secret = "test_webhook_secret_1234"
    %{bypass: bypass, secret: secret, url: "http://localhost:#{bypass.port}/webhook"}
  end

  test "delivers payload with correct HMAC signature on 200", %{
    bypass: bypass,
    secret: secret,
    url: url
  } do
    payload = %{"workflow" => "contacts", "action" => "search", "output" => "Found 3 contacts"}

    Bypass.expect_once(bypass, "POST", "/webhook", fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      [sig_header] = Plug.Conn.get_req_header(conn, "x-crm-signature")

      expected_sig =
        :crypto.mac(:hmac, :sha256, secret, body) |> Base.encode16(case: :lower)

      assert sig_header == "sha256=#{expected_sig}"
      assert Jason.decode!(body) == payload

      Plug.Conn.resp(conn, 200, "OK")
    end)

    args = %{
      "webhook_url" => url,
      "webhook_secret" => secret,
      "payload" => payload
    }

    assert :ok = perform_job(WebhookWorker, args)
  end

  test "returns error on 500 status", %{bypass: bypass, secret: secret, url: url} do
    Bypass.expect_once(bypass, "POST", "/webhook", fn conn ->
      Plug.Conn.resp(conn, 500, "Internal Server Error")
    end)

    args = %{
      "webhook_url" => url,
      "webhook_secret" => secret,
      "payload" => %{"test" => true}
    }

    assert {:error, "HTTP 500"} = perform_job(WebhookWorker, args)
  end

  test "returns error on connection failure", %{secret: secret} do
    # Use a port with no listener
    args = %{
      "webhook_url" => "http://localhost:1/webhook",
      "webhook_secret" => secret,
      "payload" => %{"test" => true}
    }

    assert {:error, _reason} = perform_job(WebhookWorker, args)
  end
end
