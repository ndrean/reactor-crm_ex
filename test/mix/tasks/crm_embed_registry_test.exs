defmodule Mix.Tasks.Crm.EmbedRegistryTest do
  # async: false: Application.put_env mutates global state
  use CrmReactor.DataCase, async: false

  alias CrmReactor.{Repo, Tenants.ModuleRegistry}
  alias Mix.Tasks.Crm.EmbedRegistry

  setup do
    # Clear seeded rows so tests control exactly which rows exist
    Repo.delete_all(ModuleRegistry)
    # Redirect Mix shell output to the test process instead of stdout
    Mix.shell(Mix.Shell.Process)
    on_exit(fn -> Mix.shell(Mix.Shell.IO) end)
    :ok
  end

  # --- Helpers ---

  defp insert_row(attrs \\ []) do
    params =
      Keyword.merge(
        [
          workflow_name: "contacts",
          action: "search",
          active: true,
          prompt_hint: "find contacts",
          hint_embedding: nil
        ],
        attrs
      )

    Repo.insert!(%ModuleRegistry{
      workflow_name: params[:workflow_name],
      action: params[:action],
      active: params[:active],
      prompt_hint: params[:prompt_hint],
      hint_embedding: params[:hint_embedding]
    })
  end

  defp with_bypass_embedder(fun) do
    bypass = Bypass.open()
    Application.put_env(:crm_reactor, :embedder, CrmReactor.AI.Embedder)
    Application.put_env(:crm_reactor, :ollama_url, "http://localhost:#{bypass.port}")

    on_exit(fn ->
      Application.put_env(:crm_reactor, :embedder, CrmReactor.MockEmbedder)
      Application.delete_env(:crm_reactor, :ollama_url)
    end)

    fun.(bypass)
  end

  defp json_resp(conn, body) do
    conn
    |> Plug.Conn.put_resp_header("content-type", "application/json")
    |> Plug.Conn.resp(200, Jason.encode!(body))
  end

  defp fake_embedding, do: List.duplicate(0.5, 4)

  # --- Tests ---

  test "embeds only rows with nil hint_embedding by default" do
    with_bypass_embedder(fn bypass ->
      row_nil = insert_row(hint_embedding: nil)
      row_existing = insert_row(action: "create", hint_embedding: [9.9, 8.8])

      Bypass.expect_once(bypass, "POST", "/api/embed", fn conn ->
        json_resp(conn, %{"embeddings" => [fake_embedding()]})
      end)

      EmbedRegistry.run([])

      assert Repo.get!(ModuleRegistry, row_nil.id).hint_embedding == fake_embedding()
      assert Repo.get!(ModuleRegistry, row_existing.id).hint_embedding == [9.9, 8.8]
    end)
  end

  test "--force re-embeds rows that already have a hint_embedding" do
    with_bypass_embedder(fn bypass ->
      row = insert_row(hint_embedding: [9.9, 8.8])

      Bypass.expect_once(bypass, "POST", "/api/embed", fn conn ->
        json_resp(conn, %{"embeddings" => [fake_embedding()]})
      end)

      EmbedRegistry.run(["--force"])

      assert Repo.get!(ModuleRegistry, row.id).hint_embedding == fake_embedding()
    end)
  end

  test "inactive rows are never processed" do
    row = insert_row(active: false, hint_embedding: nil)

    EmbedRegistry.run([])

    assert_receive {:mix_shell, :info, ["Found 0 rows to embed."]}
    assert Repo.get!(ModuleRegistry, row.id).hint_embedding == nil
  end

  test "uses 'workflow action' as embed text when prompt_hint is nil" do
    with_bypass_embedder(fn bypass ->
      insert_row(action: "count", prompt_hint: nil)

      Bypass.expect_once(bypass, "POST", "/api/embed", fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        assert Jason.decode!(body)["input"] == "contacts count"
        json_resp(conn, %{"embeddings" => [fake_embedding()]})
      end)

      EmbedRegistry.run([])
    end)
  end

  test "logs error and leaves hint_embedding nil when embedder fails" do
    # MockEmbedder (default in test env) returns {:error, :not_configured}
    row = insert_row(hint_embedding: nil)

    EmbedRegistry.run([])

    assert_receive {:mix_shell, :error, [msg]}
    assert msg =~ "[error]"
    assert msg =~ "contacts.search"
    assert Repo.get!(ModuleRegistry, row.id).hint_embedding == nil
  end

  test "prints summary with row count and Done on completion" do
    with_bypass_embedder(fn bypass ->
      insert_row()

      Bypass.expect_once(bypass, "POST", "/api/embed", fn conn ->
        json_resp(conn, %{"embeddings" => [fake_embedding()]})
      end)

      EmbedRegistry.run([])

      assert_receive {:mix_shell, :info, ["Found 1 rows to embed."]}
      assert_receive {:mix_shell, :info, ["Done."]}
    end)
  end

  test "--force flag appears in the found-rows message" do
    EmbedRegistry.run(["--force"])

    assert_receive {:mix_shell, :info, ["Found 0 rows to embed (--force)."]}
  end
end
