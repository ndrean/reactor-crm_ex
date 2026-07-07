defmodule CrmReactor.AI.QueryBuilderTest do
  use ExUnit.Case, async: false

  alias CrmReactor.AI.QueryBuilder
  alias CrmReactor.CRM.{Contact, ExecutionLog, Todo}

  # Inject a synchronous LLM stub so no HTTP calls are made
  setup do
    prev = Application.get_env(:crm_reactor, :nl2sql_adapter)

    on_exit(fn ->
      if prev,
        do: Application.put_env(:crm_reactor, :nl2sql_adapter, prev),
        else: Application.delete_env(:crm_reactor, :nl2sql_adapter)
    end)

    :ok
  end

  defp stub_llm(filters, sort_by \\ nil, sort_dir \\ "asc") do
    Application.put_env(:crm_reactor, :nl2sql_adapter, fn _prompt, _text ->
      {:ok, %{"filters" => filters, "sort_by" => sort_by, "sort_dir" => sort_dir}}
    end)
  end

  defp stub_llm_error(reason) do
    Application.put_env(:crm_reactor, :nl2sql_adapter, fn _prompt, _text ->
      {:error, reason}
    end)
  end

  # ── Schema introspection ──────────────────────────────────────────────

  test "build_query with no filters returns a valid Ecto query" do
    stub_llm([])
    assert {:ok, %Ecto.Query{}} = QueryBuilder.build_query(Todo, "tous les todos")
  end

  test "build_query works with Contact schema" do
    stub_llm([])
    assert {:ok, %Ecto.Query{}} = QueryBuilder.build_query(Contact, "tous les contacts")
  end

  # ── apply_condition variants ──────────────────────────────────────────

  test "= operator filters by exact value" do
    stub_llm([%{"field" => "subject", "op" => "=", "value" => "Rappel"}])
    {:ok, query} = QueryBuilder.build_query(Todo, "sujet Rappel")
    assert inspect(query) =~ "=="
  end

  test "!= operator" do
    stub_llm([%{"field" => "subject", "op" => "!=", "value" => "Rappel"}])
    {:ok, query} = QueryBuilder.build_query(Todo, "pas Rappel")
    assert inspect(query) =~ "!="
  end

  test "like operator adds ilike" do
    stub_llm([%{"field" => "subject", "op" => "like", "value" => "appel"}])
    {:ok, query} = QueryBuilder.build_query(Todo, "avec appel")
    assert inspect(query) =~ "ilike"
  end

  test ">= operator" do
    stub_llm([%{"field" => "due_date", "op" => ">=", "value" => "2026-07-01"}])
    {:ok, query} = QueryBuilder.build_query(Todo, "à partir du 1er juillet")
    assert inspect(query) =~ ">="
  end

  test "<= operator" do
    stub_llm([%{"field" => "due_date", "op" => "<=", "value" => "2026-07-31"}])
    {:ok, query} = QueryBuilder.build_query(Todo, "avant fin juillet")
    assert inspect(query) =~ "<="
  end

  test "> operator" do
    stub_llm([%{"field" => "due_date", "op" => ">", "value" => "2026-07-01"}])
    {:ok, query} = QueryBuilder.build_query(Todo, "après le 1er juillet")
    assert inspect(query) =~ ">"
  end

  test "< operator" do
    stub_llm([%{"field" => "due_date", "op" => "<", "value" => "2026-06-01"}])
    {:ok, query} = QueryBuilder.build_query(Todo, "avant juin")
    assert inspect(query) =~ "<"
  end

  # ── apply_sort variants ───────────────────────────────────────────────

  test "sort_by with desc direction" do
    stub_llm([], "due_date", "desc")
    {:ok, query} = QueryBuilder.build_query(Todo, "todos triés par date décroissante")
    assert inspect(query) =~ "order_by"
    assert inspect(query) =~ "desc"
  end

  test "sort_by with asc direction (default)" do
    stub_llm([], "due_date", "asc")
    {:ok, query} = QueryBuilder.build_query(Todo, "todos triés par date croissante")
    assert inspect(query) =~ "order_by"
  end

  test "sort_by with unknown field is ignored" do
    stub_llm([], "nonexistent_field", "asc")
    {:ok, query} = QueryBuilder.build_query(Todo, "trié par champ inconnu")
    refute inspect(query) =~ "order_by"
  end

  test "sort_by nil skips ordering" do
    stub_llm([], nil, "asc")
    {:ok, query} = QueryBuilder.build_query(Todo, "sans tri")
    refute inspect(query) =~ "order_by"
  end

  test "sort_by with unknown field and desc direction is ignored" do
    stub_llm([], "nonexistent_field", "desc")
    {:ok, query} = QueryBuilder.build_query(Todo, "trié desc par champ inconnu")
    refute inspect(query) =~ "order_by"
  end

  # ── cast_value variants ───────────────────────────────────────────────

  test "date string is cast to Date struct" do
    stub_llm([%{"field" => "due_date", "op" => "=", "value" => "2026-07-15"}])
    {:ok, query} = QueryBuilder.build_query(Todo, "due le 15 juillet")
    assert inspect(query) =~ "~D[2026-07-15]"
  end

  test "invalid date string passes through as-is" do
    stub_llm([%{"field" => "due_date", "op" => "=", "value" => "not-a-date"}])
    {:ok, query} = QueryBuilder.build_query(Todo, "date invalide")
    assert inspect(query) =~ "not-a-date"
  end

  test "boolean true string is cast" do
    stub_llm([%{"field" => "done", "op" => "=", "value" => "true"}])
    {:ok, query} = QueryBuilder.build_query(Todo, "todos faits")
    assert inspect(query) =~ "true"
  end

  test "boolean false string is cast" do
    stub_llm([%{"field" => "done", "op" => "=", "value" => "false"}])
    {:ok, query} = QueryBuilder.build_query(Todo, "todos non faits")
    assert inspect(query) =~ "false"
  end

  test "boolean native true passes through" do
    stub_llm([%{"field" => "done", "op" => "=", "value" => true}])
    {:ok, query} = QueryBuilder.build_query(Todo, "todos faits")
    assert inspect(query) =~ "true"
  end

  test "string field passes through unchanged" do
    stub_llm([%{"field" => "subject", "op" => "=", "value" => "Rappel"}])
    {:ok, query} = QueryBuilder.build_query(Todo, "subject Rappel")
    assert inspect(query) =~ "Rappel"
  end

  # ── validate_filters error paths ─────────────────────────────────────

  test "filter with unknown field is rejected" do
    stub_llm([%{"field" => "secret_column", "op" => "=", "value" => "x"}])
    assert {:error, {:rejected_filters, _}} = QueryBuilder.build_query(Todo, "champ inconnu")
  end

  test "filter with invalid op is rejected" do
    stub_llm([%{"field" => "subject", "op" => "INJECT", "value" => "x"}])
    assert {:error, {:rejected_filters, _}} = QueryBuilder.build_query(Todo, "op invalide")
  end

  test "filter with non-string field key is rejected" do
    Application.put_env(:crm_reactor, :nl2sql_adapter, fn _p, _t ->
      {:ok,
       %{
         "filters" => [%{"field" => 123, "op" => "=", "value" => "x"}],
         "sort_by" => nil,
         "sort_dir" => "asc"
       }}
    end)

    assert {:error, {:rejected_filters, _}} = QueryBuilder.build_query(Todo, "champ numérique")
  end

  test "non-list filters returns invalid_format error" do
    Application.put_env(:crm_reactor, :nl2sql_adapter, fn _p, _t ->
      {:ok, %{"filters" => "not a list", "sort_by" => nil, "sort_dir" => "asc"}}
    end)

    assert {:error, :invalid_format} = QueryBuilder.build_query(Todo, "mauvais format")
  end

  # ── LLM error propagation ─────────────────────────────────────────────

  test "LLM error is propagated as {:error, reason}" do
    stub_llm_error("timeout")
    assert {:error, "timeout"} = QueryBuilder.build_query(Todo, "erreur LLM")
  end

  # ── format_type edge cases (via schema introspection) ────────────────

  test "utc_datetime field type is formatted correctly" do
    stub_llm([])
    # ExecutionLog has logged_at :utc_datetime — triggers format_type(:utc_datetime)
    assert {:ok, %Ecto.Query{}} = QueryBuilder.build_query(ExecutionLog, "tous les logs")
  end

  test "encrypted/custom field type falls through to format_type(other)" do
    stub_llm([])
    # Contact.email is CrmReactor.Encrypted.Binary — triggers format_type(other)
    assert {:ok, %Ecto.Query{}} = QueryBuilder.build_query(Contact, "tous les contacts")
  end

  test "cast_value for utc_datetime string is cast to DateTime" do
    stub_llm([%{"field" => "logged_at", "op" => ">=", "value" => "2026-01-01T00:00:00Z"}])
    {:ok, query} = QueryBuilder.build_query(ExecutionLog, "logs depuis janvier")
    assert inspect(query) =~ ">="
  end

  test "cast_value for invalid utc_datetime string passes through" do
    stub_llm([%{"field" => "logged_at", "op" => "=", "value" => "not-a-datetime"}])
    {:ok, query} = QueryBuilder.build_query(ExecutionLog, "logs invalides")
    assert inspect(query) =~ "not-a-datetime"
  end

  test "cast_value for integer field with string value" do
    stub_llm([%{"field" => "total_tokens", "op" => ">=", "value" => "100"}])
    {:ok, query} = QueryBuilder.build_query(ExecutionLog, "logs avec beaucoup de tokens")
    assert inspect(query) =~ ">="
  end

  test "cast_value for integer field with integer value" do
    stub_llm([%{"field" => "total_tokens", "op" => ">=", "value" => 100}])
    {:ok, query} = QueryBuilder.build_query(ExecutionLog, "logs tokens")
    assert inspect(query) =~ ">="
  end

  test "cast_value for integer field with unparseable string passes through as-is" do
    stub_llm([%{"field" => "total_tokens", "op" => "=", "value" => "not-a-number"}])
    {:ok, query} = QueryBuilder.build_query(ExecutionLog, "tokens invalides")
    assert inspect(query) =~ "not-a-number"
  end

  # ── HTTP path — Mistral and Ollama (Bypass) ───────────────────────────

  describe "HTTP path" do
    setup do
      prev_adapter = Application.get_env(:crm_reactor, :nl2sql_adapter)
      prev_url = Application.get_env(:crm_reactor, :mistral_api_url)
      prev_key = Application.get_env(:crm_reactor, :mistral_api_key)
      prev_ollama = Application.get_env(:crm_reactor, :ollama_url)

      Application.delete_env(:crm_reactor, :nl2sql_adapter)

      bypass = Bypass.open()
      Application.put_env(:crm_reactor, :mistral_api_url, "http://localhost:#{bypass.port}")
      Application.put_env(:crm_reactor, :mistral_api_key, "test-key")

      on_exit(fn ->
        for {key, val} <- [
              nl2sql_adapter: prev_adapter,
              mistral_api_url: prev_url,
              mistral_api_key: prev_key,
              ollama_url: prev_ollama
            ] do
          if val,
            do: Application.put_env(:crm_reactor, key, val),
            else: Application.delete_env(:crm_reactor, key)
        end
      end)

      {:ok, bypass: bypass}
    end

    test "Mistral 200 success returns Ecto query", %{bypass: bypass} do
      Bypass.expect_once(bypass, "POST", "/v1/chat/completions", fn conn ->
        body =
          Jason.encode!(%{
            "choices" => [
              %{
                "message" => %{
                  "content" => ~s({"filters":[],"sort_by":null,"sort_dir":"asc"})
                }
              }
            ]
          })

        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.send_resp(200, body)
      end)

      assert {:ok, %Ecto.Query{}} = QueryBuilder.build_query(Todo, "tous les todos")
    end

    test "Mistral non-200 falls back to Ollama success", %{bypass: bypass} do
      ollama_bypass = Bypass.open()
      Application.put_env(:crm_reactor, :ollama_url, "http://localhost:#{ollama_bypass.port}")

      Bypass.expect_once(bypass, "POST", "/v1/chat/completions", fn conn ->
        Plug.Conn.send_resp(conn, 500, "error")
      end)

      Bypass.expect_once(ollama_bypass, "POST", "/api/chat", fn conn ->
        body =
          Jason.encode!(%{
            "message" => %{
              "content" => ~s({"filters":[],"sort_by":null,"sort_dir":"asc"})
            }
          })

        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.send_resp(200, body)
      end)

      assert {:ok, %Ecto.Query{}} = QueryBuilder.build_query(Todo, "fallback Ollama")
    end

    test "Ollama non-200 returns error", %{bypass: bypass} do
      ollama_bypass = Bypass.open()
      Application.put_env(:crm_reactor, :ollama_url, "http://localhost:#{ollama_bypass.port}")

      Bypass.expect_once(bypass, "POST", "/v1/chat/completions", fn conn ->
        Plug.Conn.send_resp(conn, 500, "error")
      end)

      Bypass.expect_once(ollama_bypass, "POST", "/api/chat", fn conn ->
        Plug.Conn.send_resp(conn, 503, "unavailable")
      end)

      assert {:error, "Ollama error 503"} = QueryBuilder.build_query(Todo, "erreur Ollama")
    end

    test "Mistral connection refused falls back; Ollama connection refused returns error",
         %{bypass: bypass} do
      Bypass.down(bypass)

      ollama_bypass = Bypass.open()
      Application.put_env(:crm_reactor, :ollama_url, "http://localhost:#{ollama_bypass.port}")
      Bypass.down(ollama_bypass)

      assert {:error, _} = QueryBuilder.build_query(Todo, "tout échoue")
    end
  end

  # ── Multiple filters ─────────────────────────────────────────────────

  test "multiple filters are all applied" do
    stub_llm([
      %{"field" => "done", "op" => "=", "value" => false},
      %{"field" => "due_date", "op" => "<=", "value" => "2026-07-31"}
    ])

    {:ok, query} = QueryBuilder.build_query(Todo, "todos actifs avant fin juillet")
    sql = inspect(query)
    assert sql =~ "false"
    assert sql =~ "<="
  end
end
