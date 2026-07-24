defmodule CrmReactorWeb.InboundEmailControllerTest do
  use CrmReactorWeb.ConnCase, async: false

  import Mox

  alias CrmReactor.Emails.IncomingEmail
  alias CrmReactor.Repo

  @secret "test-email-secret"

  setup :set_mox_global
  setup :verify_on_exit!

  defp sign_and_post(conn, path, params) do
    body = Jason.encode!(params)

    signature =
      :crypto.mac(:hmac, :sha256, @secret, body)
      |> Base.encode16(case: :lower)

    conn
    |> put_req_header("content-type", "application/json")
    |> put_req_header("x-webhook-signature", "sha256=#{signature}")
    |> post(path, body)
  end

  defp base_params do
    %{
      "from" => "sender@example.com",
      "subject" => "Test subject",
      "body" => "Test body"
    }
  end

  describe "create/2 authentication" do
    test "rejects request without signature", %{conn: conn} do
      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post(~p"/webhook/email", Jason.encode!(base_params()))

      assert conn.status == 401
      assert conn.resp_body =~ "Missing or invalid signature"
    end

    test "rejects request with wrong signature", %{conn: conn} do
      body = Jason.encode!(base_params())

      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> put_req_header(
          "x-webhook-signature",
          "sha256=0000000000000000000000000000000000000000000000000000000000000000"
        )
        |> post(~p"/webhook/email", body)

      assert conn.status == 401
      assert conn.resp_body =~ "Invalid signature"
    end
  end

  describe "create/2 without attachments" do
    test "creates incoming email", %{conn: conn} do
      conn = sign_and_post(conn, ~p"/webhook/email", base_params())

      assert json_response(conn, 200)["ok"] == true

      email = Repo.one!(IncomingEmail)
      assert email.from_address == "sender@example.com"
      assert email.subject == "Test subject"
      assert email.attachments == []
    end

    test "rejects missing from field", %{conn: conn} do
      conn = sign_and_post(conn, ~p"/webhook/email", %{"subject" => "Test"})

      assert json_response(conn, 400)["error"] == "Missing required field: from"
    end
  end

  describe "create/2 with attachments" do
    test "stores valid attachment", %{conn: conn} do
      content = "hello world"
      b64 = Base.encode64(content)

      CrmReactor.MockStorage
      |> expect(:put, fn "inbound", _filename, ^content ->
        {:ok, "inbound/abc-test.txt"}
      end)

      params =
        Map.put(base_params(), "attachments", [
          %{"filename" => "test.txt", "mimeType" => "text/plain", "content" => b64}
        ])

      conn = sign_and_post(conn, ~p"/webhook/email", params)

      assert json_response(conn, 200)["ok"] == true

      email = Repo.one!(IncomingEmail)
      assert length(email.attachments) == 1
      [att] = email.attachments
      assert att["original_filename"] == "test.txt"
      assert att["storage_key"] == "inbound/abc-test.txt"
      assert att["content_type"] == "text/plain"
      assert att["size"] == byte_size(content)
    end

    test "rejects invalid base64", %{conn: conn} do
      params =
        Map.put(base_params(), "attachments", [
          %{"filename" => "bad.txt", "mimeType" => "text/plain", "content" => "!!!not-base64!!!"}
        ])

      conn = sign_and_post(conn, ~p"/webhook/email", params)

      assert json_response(conn, 422)["error"] == "Invalid base64 attachment content"
    end

    test "rejects total size exceeding 10MB", %{conn: conn} do
      big_content = :crypto.strong_rand_bytes(4 * 1024 * 1024)
      b64 = Base.encode64(big_content)

      CrmReactor.MockStorage
      |> expect(:put, 2, fn "inbound", _filename, _content ->
        {:ok, "inbound/stored-#{System.unique_integer([:positive])}.bin"}
      end)
      |> expect(:delete, 2, fn _key -> :ok end)

      params =
        Map.put(base_params(), "attachments", [
          %{"filename" => "big1.bin", "mimeType" => "application/octet-stream", "content" => b64},
          %{"filename" => "big2.bin", "mimeType" => "application/octet-stream", "content" => b64},
          %{"filename" => "big3.bin", "mimeType" => "application/octet-stream", "content" => b64}
        ])

      conn = sign_and_post(conn, ~p"/webhook/email", params)

      assert json_response(conn, 422)["error"] == "Total attachments exceed 10MB limit"
    end

    test "cleans up on storage failure", %{conn: conn} do
      content1 = "file one"
      content2 = "file two"

      CrmReactor.MockStorage
      |> expect(:put, fn "inbound", _filename, ^content1 ->
        {:ok, "inbound/ok-file1.txt"}
      end)
      |> expect(:put, fn "inbound", _filename, ^content2 ->
        {:error, :storage_unavailable}
      end)
      |> expect(:delete, fn "inbound/ok-file1.txt" -> :ok end)

      params =
        Map.put(base_params(), "attachments", [
          %{
            "filename" => "f1.txt",
            "mimeType" => "text/plain",
            "content" => Base.encode64(content1)
          },
          %{
            "filename" => "f2.txt",
            "mimeType" => "text/plain",
            "content" => Base.encode64(content2)
          }
        ])

      conn = sign_and_post(conn, ~p"/webhook/email", params)

      assert json_response(conn, 422)["error"] == "Failed to store attachment"
      assert Repo.aggregate(IncomingEmail, :count) == 0
    end
  end
end
