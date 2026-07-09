defmodule CrmReactor.AI.EmbedderTest do
  # async: false because Application.put_env(:crm_reactor, :ollama_url) mutates global state
  use ExUnit.Case, async: false

  # Suppress Logger warnings from intentional error-path tests
  @moduletag capture_log: true

  alias CrmReactor.AI.Embedder

  setup do
    bypass = Bypass.open()
    Application.put_env(:crm_reactor, :ollama_url, "http://localhost:#{bypass.port}")
    on_exit(fn -> Application.delete_env(:crm_reactor, :ollama_url) end)
    {:ok, bypass: bypass}
  end

  defp json_resp(conn, status, body) do
    conn
    |> Plug.Conn.put_resp_header("content-type", "application/json")
    |> Plug.Conn.resp(status, Jason.encode!(body))
  end

  test "returns {:ok, embedding} on successful response", %{bypass: bypass} do
    embedding = Enum.map(1..1024, fn _ -> :rand.uniform() end)

    Bypass.expect_once(bypass, "POST", "/api/embed", fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      decoded = Jason.decode!(body)
      assert decoded["model"] == "mxbai-embed-large"
      assert is_binary(decoded["input"])

      json_resp(conn, 200, %{"embeddings" => [embedding]})
    end)

    assert {:ok, result} = Embedder.embed("hello world")
    assert length(result) == 1024
  end

  test "returns {:error, _} on HTTP error status", %{bypass: bypass} do
    Bypass.expect_once(bypass, "POST", "/api/embed", fn conn ->
      json_resp(conn, 500, %{"error" => "model not found"})
    end)

    assert {:error, _reason} = Embedder.embed("hello")
  end

  test "returns {:error, :unexpected_response} when embeddings key is missing", %{bypass: bypass} do
    Bypass.expect_once(bypass, "POST", "/api/embed", fn conn ->
      json_resp(conn, 200, %{"something" => "else"})
    end)

    assert {:error, :unexpected_response} = Embedder.embed("hello")
  end

  test "returns {:error, reason} on transport error", %{bypass: bypass} do
    Bypass.down(bypass)

    assert {:error, %Req.TransportError{}} = Embedder.embed("hello")
  end
end
