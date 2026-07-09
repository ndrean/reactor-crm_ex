defmodule CrmReactor.AI.SimilarityTest do
  use ExUnit.Case, async: true

  alias CrmReactor.AI.Similarity

  defp entry(workflow, embedding) do
    %{workflow_name: workflow, hint_embedding: embedding}
  end

  test "returns nil when registry is empty" do
    assert Similarity.top_workflow([1.0, 0.0], []) == nil
  end

  test "returns nil when all entries have nil embeddings" do
    entries = [entry("contacts", nil), entry("todos", nil)]
    assert Similarity.top_workflow([1.0, 0.0], entries) == nil
  end

  test "returns nil when all entries have empty embeddings" do
    entries = [entry("contacts", []), entry("todos", [])]
    assert Similarity.top_workflow([1.0, 0.0], entries) == nil
  end

  test "returns the workflow with highest cosine similarity" do
    # query aligns with contacts vector [1, 0]
    query = [1.0, 0.0]

    entries = [
      entry("contacts", [1.0, 0.0]),
      entry("todos", [0.0, 1.0])
    ]

    assert Similarity.top_workflow(query, entries) == "contacts"
  end

  test "parallel vectors yield cosine = 1 (same workflow wins)" do
    query = [1.0, 0.0]
    entries = [entry("contacts", [1.0, 0.0])]

    result = Similarity.top_workflow(query, entries)
    assert result == "contacts"
  end

  test "orthogonal vectors yield cosine = 0 (other workflow wins)" do
    query = [1.0, 0.0]

    entries = [
      entry("contacts", [0.0, 1.0]),
      entry("todos", [1.0, 0.0])
    ]

    assert Similarity.top_workflow(query, entries) == "todos"
  end

  test "skips entries with nil embedding, picks best from remaining" do
    query = [1.0, 0.0]

    entries = [
      entry("contacts", nil),
      entry("todos", [1.0, 0.0])
    ]

    assert Similarity.top_workflow(query, entries) == "todos"
  end

  test "groups multiple entries per workflow and returns max score" do
    query = [1.0, 0.0]
    # contacts has two entries: one with low similarity [0,1], one with high [1,0]
    # todos has one entry: medium [0.7, 0.7] normalized below
    entries = [
      entry("contacts", [0.0, 1.0]),
      entry("contacts", [1.0, 0.0]),
      entry("todos", [0.7071, 0.7071])
    ]

    assert Similarity.top_workflow(query, entries) == "contacts"
  end

  # ── top_n_workflows/3 ──────────────────────────────────────────────────────

  defp example(workflow, embedding) do
    %{workflow_name: workflow, embedding: embedding}
  end

  describe "top_n_workflows/3" do
    test "returns [] when examples list is empty" do
      assert Similarity.top_n_workflows([1.0, 0.0], []) == []
    end

    test "returns [] when all entries have nil embeddings" do
      examples = [example("contacts", nil), example("todos", nil)]
      assert Similarity.top_n_workflows([1.0, 0.0], examples) == []
    end

    test "returns [] when all entries have empty embeddings" do
      examples = [example("contacts", []), example("todos", [])]
      assert Similarity.top_n_workflows([1.0, 0.0], examples) == []
    end

    test "returns top-n workflows sorted by score descending" do
      query = [1.0, 0.0]

      examples = [
        example("contacts", [1.0, 0.0]),
        example("todos", [0.0, 1.0]),
        example("data", [0.7071, 0.7071])
      ]

      result = Similarity.top_n_workflows(query, examples, 2)
      assert length(result) == 2
      [{w1, s1}, {w2, s2}] = result
      assert w1 == "contacts"
      assert s1 > s2
      assert w2 == "data"
    end

    test "takes at most n results" do
      query = [1.0, 0.0]

      examples = [
        example("contacts", [1.0, 0.0]),
        example("todos", [0.7071, 0.7071]),
        example("data", [0.0, 1.0])
      ]

      result = Similarity.top_n_workflows(query, examples, 1)
      assert length(result) == 1
      assert elem(List.first(result), 0) == "contacts"
    end

    test "groups by workflow_name and takes max score per group" do
      query = [1.0, 0.0]

      # contacts has low + high score; result should use high score
      examples = [
        example("contacts", [0.0, 1.0]),
        example("contacts", [1.0, 0.0]),
        example("todos", [0.7071, 0.7071])
      ]

      result = Similarity.top_n_workflows(query, examples, 2)
      assert length(result) == 2
      [{w1, s1}, _] = result
      assert w1 == "contacts"
      assert_in_delta s1, 1.0, 0.001
    end

    test "skips nil embeddings and returns results from valid entries" do
      query = [1.0, 0.0]

      examples = [
        example("contacts", nil),
        example("todos", [1.0, 0.0])
      ]

      result = Similarity.top_n_workflows(query, examples, 2)
      assert length(result) == 1
      assert elem(List.first(result), 0) == "todos"
    end
  end
end
