defmodule CrmReactor.Workers.WebhookWorkerTest do
  use CrmReactor.DataCase
  use Oban.Testing, repo: CrmReactor.Repo

  alias CrmReactor.Workers.WebhookWorker

  @secret "test_webhook_secret_1234"

  test "delivers payload with correct HMAC signature on 200" do
    test_pid = self()
    payload = %{"workflow" => "contacts", "action" => "search", "output" => "Found 3 contacts"}

    {:ok, port, pid} =
      CrmReactor.TestPlugServer.start(fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        [sig_header] = Plug.Conn.get_req_header(conn, "x-crm-signature")

        send(test_pid, {:received, body, sig_header})

        Plug.Conn.resp(conn, 200, "OK")
      end)

    on_exit(fn -> CrmReactor.TestPlugServer.stop(pid) end)

    args = %{
      "webhook_url" => "http://localhost:#{port}/webhook",
      "webhook_secret" => @secret,
      "payload" => payload
    }

    assert :ok = perform_job(WebhookWorker, args)

    assert_receive {:received, body, sig_header}

    expected_sig =
      :crypto.mac(:hmac, :sha256, @secret, body) |> Base.encode16(case: :lower)

    assert sig_header == "sha256=#{expected_sig}"
    assert Jason.decode!(body) == payload
  end

  test "returns error on 500 status" do
    {:ok, port, pid} =
      CrmReactor.TestPlugServer.start(fn conn ->
        Plug.Conn.resp(conn, 500, "Internal Server Error")
      end)

    on_exit(fn -> CrmReactor.TestPlugServer.stop(pid) end)

    args = %{
      "webhook_url" => "http://localhost:#{port}/webhook",
      "webhook_secret" => @secret,
      "payload" => %{"test" => true}
    }

    assert {:error, "HTTP 500"} = perform_job(WebhookWorker, args)
  end

  test "returns error on connection failure" do
    args = %{
      "webhook_url" => "http://localhost:1/webhook",
      "webhook_secret" => @secret,
      "payload" => %{"test" => true}
    }

    assert {:error, _reason} = perform_job(WebhookWorker, args)
  end
end
