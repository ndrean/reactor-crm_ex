defmodule CrmReactor.Workers.ExampleReviewWorkerTest do
  use CrmReactor.DataCase

  alias CrmReactor.AI.RoutingSignal
  alias CrmReactor.Repo
  alias CrmReactor.Tenants.RegistryExample
  alias CrmReactor.Workers.ExampleReviewWorker

  use Oban.Testing, repo: CrmReactor.Repo
  import Ecto.Query

  setup do
    Repo.delete_all(from(s in RoutingSignal, where: s.tenant_id == "review_test"))
    Repo.delete_all(from(e in RegistryExample, where: e.phrase == "supprimer le contact Marie"))

    bypass = Bypass.open()

    original_url = Application.get_env(:crm_reactor, :mistral_api_url)
    original_key = Application.get_env(:crm_reactor, :mistral_api_key)
    original_embedder = Application.get_env(:crm_reactor, :embedder)

    Application.put_env(:crm_reactor, :mistral_api_url, "http://localhost:#{bypass.port}")
    Application.put_env(:crm_reactor, :mistral_api_key, "test-key")
    Application.put_env(:crm_reactor, :embedder, CrmReactor.MockEmbedder)

    on_exit(fn ->
      if original_url,
        do: Application.put_env(:crm_reactor, :mistral_api_url, original_url),
        else: Application.delete_env(:crm_reactor, :mistral_api_url)

      if original_key,
        do: Application.put_env(:crm_reactor, :mistral_api_key, original_key),
        else: Application.delete_env(:crm_reactor, :mistral_api_key)

      if original_embedder,
        do: Application.put_env(:crm_reactor, :embedder, original_embedder),
        else: Application.delete_env(:crm_reactor, :embedder)
    end)

    %{bypass: bypass}
  end

  defp insert_mismatch(attrs \\ %{}) do
    defaults = %{
      tenant_id: "review_test",
      raw_input: "supprimer le contact Marie",
      cosine_workflow: "contacts",
      cosine_score: 0.8,
      pass1_workflow: "todos",
      pass1_confidence: 0.75,
      pass2_workflow: "contacts",
      llm_confirmed: false,
      user_corrected: false,
      reviewed: false
    }

    %RoutingSignal{}
    |> RoutingSignal.changeset(Map.merge(defaults, attrs))
    |> Repo.insert!()
  end

  defp mock_verdict_response(bypass, signal_id, workflow, good) do
    Bypass.expect_once(bypass, "POST", "/v1/chat/completions", fn conn ->
      verdicts =
        Jason.encode!(%{
          "verdicts" => [
            %{"id" => signal_id, "correct_workflow" => workflow, "is_good_example" => good}
          ]
        })

      body =
        Jason.encode!(%{
          "choices" => [%{"message" => %{"content" => verdicts}}],
          "usage" => %{"prompt_tokens" => 100, "completion_tokens" => 50, "total_tokens" => 150}
        })

      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.resp(200, body)
    end)
  end

  describe "perform/1 filtering" do
    test "no-ops when no unreviewed mismatches exist" do
      assert :ok = perform_job(ExampleReviewWorker, %{})
    end

    test "ignores already-reviewed signals" do
      insert_mismatch(%{reviewed: true})
      assert :ok = perform_job(ExampleReviewWorker, %{})
    end

    test "ignores signals where pass1 == pass2" do
      insert_mismatch(%{pass1_workflow: "contacts", pass2_workflow: "contacts"})
      assert :ok = perform_job(ExampleReviewWorker, %{})
    end

    test "ignores signals older than 24h" do
      old_time = DateTime.utc_now() |> DateTime.add(-25 * 3600, :second)
      signal = insert_mismatch()

      from(s in RoutingSignal, where: s.id == ^signal.id)
      |> Repo.update_all(set: [inserted_at: old_time])

      assert :ok = perform_job(ExampleReviewWorker, %{})

      updated = Repo.get!(RoutingSignal, signal.id)
      assert updated.reviewed == false
    end
  end

  describe "review_and_learn pipeline" do
    test "inserts example and marks reviewed when judge approves", %{bypass: bypass} do
      signal = insert_mismatch()
      mock_verdict_response(bypass, signal.id, "contacts", true)

      assert :ok = perform_job(ExampleReviewWorker, %{})

      # Signal marked as reviewed
      updated = Repo.get!(RoutingSignal, signal.id)
      assert updated.reviewed == true

      # New example inserted
      example =
        Repo.one(from(e in RegistryExample, where: e.phrase == "supprimer le contact Marie"))

      assert example
      assert example.workflow_name == "contacts"
    end

    test "marks reviewed but does not insert example when judge rejects", %{bypass: bypass} do
      signal = insert_mismatch()
      mock_verdict_response(bypass, signal.id, "contacts", false)

      before_count = Repo.aggregate(RegistryExample, :count)
      assert :ok = perform_job(ExampleReviewWorker, %{})

      # Signal marked as reviewed
      updated = Repo.get!(RoutingSignal, signal.id)
      assert updated.reviewed == true

      # No new example inserted
      after_count = Repo.aggregate(RegistryExample, :count)
      assert after_count == before_count
    end

    test "handles multiple signals with mixed verdicts", %{bypass: bypass} do
      s1 = insert_mismatch(%{raw_input: "supprimer le contact Marie", pass1_workflow: "todos"})

      s2 =
        insert_mismatch(%{
          raw_input: "liste mes tâches",
          pass1_workflow: "contacts",
          pass2_workflow: "todos"
        })

      Bypass.expect_once(bypass, "POST", "/v1/chat/completions", fn conn ->
        verdicts =
          Jason.encode!(%{
            "verdicts" => [
              %{"id" => s1.id, "correct_workflow" => "contacts", "is_good_example" => true},
              %{"id" => s2.id, "correct_workflow" => "todos", "is_good_example" => false}
            ]
          })

        body =
          Jason.encode!(%{
            "choices" => [%{"message" => %{"content" => verdicts}}],
            "usage" => %{"prompt_tokens" => 100, "completion_tokens" => 50, "total_tokens" => 150}
          })

        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, body)
      end)

      assert :ok = perform_job(ExampleReviewWorker, %{})

      # Both marked reviewed
      assert Repo.get!(RoutingSignal, s1.id).reviewed == true
      assert Repo.get!(RoutingSignal, s2.id).reviewed == true

      # Only s1 created an example (good=true)
      assert Repo.one(from(e in RegistryExample, where: e.phrase == "supprimer le contact Marie"))
      refute Repo.one(from(e in RegistryExample, where: e.phrase == "liste mes tâches"))
    end

    test "marks reviewed even when Mistral returns non-200", %{bypass: bypass} do
      signal = insert_mismatch()

      Bypass.expect_once(bypass, "POST", "/v1/chat/completions", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(500, Jason.encode!(%{"error" => "internal"}))
      end)

      assert :ok = perform_job(ExampleReviewWorker, %{})

      updated = Repo.get!(RoutingSignal, signal.id)
      assert updated.reviewed == true
    end

    test "handles malformed JSON in LLM response", %{bypass: bypass} do
      signal = insert_mismatch()

      Bypass.expect_once(bypass, "POST", "/v1/chat/completions", fn conn ->
        body =
          Jason.encode!(%{
            "choices" => [%{"message" => %{"content" => "not valid json {"}}],
            "usage" => %{"prompt_tokens" => 10, "completion_tokens" => 5, "total_tokens" => 15}
          })

        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, body)
      end)

      assert :ok = perform_job(ExampleReviewWorker, %{})

      updated = Repo.get!(RoutingSignal, signal.id)
      assert updated.reviewed == true
    end

    test "handles unexpected response shape from LLM", %{bypass: bypass} do
      signal = insert_mismatch()

      Bypass.expect_once(bypass, "POST", "/v1/chat/completions", fn conn ->
        body =
          Jason.encode!(%{
            "choices" => [%{"message" => %{"content" => Jason.encode!(%{"something" => "else"})}}],
            "usage" => %{"prompt_tokens" => 10, "completion_tokens" => 5, "total_tokens" => 15}
          })

        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, body)
      end)

      assert :ok = perform_job(ExampleReviewWorker, %{})

      updated = Repo.get!(RoutingSignal, signal.id)
      assert updated.reviewed == true
    end
  end
end
