defmodule CrmReactor.AI.Similarity do
  @moduledoc """
  Computes cosine similarity between a query embedding and stored embeddings.

  Uses `defn` to batch all cosine computations into a single vectorized
  matrix operation — one BEAM→native roundtrip regardless of entry count.

  `top_workflow/2` — used with `module_registry` hint embeddings (action-level).
  `top_n_workflows/3` — used with `registry_examples` (workflow-level phrases),
    returns top-n `{workflow_name, score}` pairs sorted by score descending.
  """

  import Nx.Defn

  @doc "Returns the workflow name with highest max cosine similarity, or nil if no embeddings."
  def top_workflow(query_embedding, registry_entries) do
    entries_with_embeddings =
      Enum.filter(registry_entries, &(&1.hint_embedding != nil and &1.hint_embedding != []))

    case entries_with_embeddings do
      [] ->
        nil

      entries ->
        workflows = Enum.map(entries, & &1.workflow_name)
        embeddings = Enum.map(entries, & &1.hint_embedding)
        scores = batch_cosine_scores(query_embedding, embeddings)

        Enum.zip(workflows, scores)
        |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
        |> Enum.map(fn {workflow, scores} -> {workflow, Enum.max(scores)} end)
        |> Enum.max_by(&elem(&1, 1))
        |> elem(0)
    end
  end

  @doc """
  Returns the top-n `{workflow_name, score}` pairs from example entries, sorted by score
  descending. Groups by workflow_name and takes the max score per group.
  Returns [] when no entries have embeddings.
  """
  def top_n_workflows(query_embedding, example_entries, n \\ 2) do
    entries_with_embeddings =
      Enum.filter(example_entries, &(&1.embedding != nil and &1.embedding != []))

    case entries_with_embeddings do
      [] ->
        []

      entries ->
        workflows = Enum.map(entries, & &1.workflow_name)
        embeddings = Enum.map(entries, & &1.embedding)
        scores = batch_cosine_scores(query_embedding, embeddings)

        Enum.zip(workflows, scores)
        |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
        |> Enum.map(fn {workflow, scores} -> {workflow, Enum.max(scores)} end)
        |> Enum.sort_by(&elem(&1, 1), :desc)
        |> Enum.take(n)
    end
  end

  # Stacks all embeddings into a matrix and computes cosine similarity
  # in a single vectorized operation. Returns a list of floats.
  defp batch_cosine_scores(query_embedding, embeddings_list) do
    query = Nx.tensor(query_embedding, type: :f32)
    matrix = Nx.stack(Enum.map(embeddings_list, &Nx.tensor(&1, type: :f32)))

    cosine_all(query, matrix)
    |> Nx.to_flat_list()
  end

  @doc "Warms up the EXLA JIT cache by running a dummy computation."
  def warmup do
    q = Nx.tensor(List.duplicate(0.0, 4), type: :f32)
    m = Nx.tensor([List.duplicate(0.0, 4)], type: :f32)
    cosine_all(q, m)
    :ok
  end

  # Single defn call: query (1D) against matrix (NxD) → N scores
  defn cosine_all(query, matrix) do
    q = Nx.reshape(query, {1, :auto})
    dots = Nx.dot(q, Nx.transpose(matrix))
    q_norm = Nx.LinAlg.norm(q)
    m_norms = Nx.LinAlg.norm(matrix, axes: [1])
    Nx.reshape(dots, {:auto}) / (q_norm * m_norms)
  end
end
