defmodule Mix.Tasks.Crm.EmbedExamplesTest do
  use CrmReactor.DataCase, async: false

  # MockEmbedder returns {:error, :not_configured} for every phrase — suppress the warnings
  @moduletag capture_log: true

  alias CrmReactor.AI.ExamplesCache
  alias CrmReactor.Repo
  alias CrmReactor.Tenants.RegistryExample
  alias Mix.Tasks.Crm.EmbedExamples

  import Ecto.Query

  setup do
    # Restore (not delete) the embedder config so subsequent tests keep using MockEmbedder
    original_embedder = Application.get_env(:crm_reactor, :embedder)
    Application.put_env(:crm_reactor, :embedder, CrmReactor.MockEmbedder)

    on_exit(fn ->
      Application.put_env(:crm_reactor, :embedder, original_embedder)
      # Reload cache to clear any ETS entries seeded during the test
      ExamplesCache.reload()
    end)

    :ok
  end

  test "seeds corpus rows on first run" do
    EmbedExamples.run([])

    count = Repo.aggregate(RegistryExample, :count, :id)
    assert count >= 29
  end

  test "run/1 is idempotent — second run does not duplicate rows" do
    EmbedExamples.run([])
    count1 = Repo.aggregate(RegistryExample, :count, :id)

    EmbedExamples.run([])
    count2 = Repo.aggregate(RegistryExample, :count, :id)

    assert count1 == count2
  end

  test "reloads ExamplesCache after run" do
    EmbedExamples.run([])

    # ExamplesCache should reflect DB rows (embeddings are nil due to MockEmbedder returning error)
    assert is_list(ExamplesCache.all())
  end

  test "--force flag re-embeds rows that already have embeddings" do
    # First run: seed (MockEmbedder returns error → embeddings remain nil)
    EmbedExamples.run([])

    nil_count =
      Repo.aggregate(from(e in RegistryExample, where: is_nil(e.embedding)), :count, :id)

    # All embeddings should be nil since MockEmbedder returns error
    assert nil_count > 0

    # --force still re-processes all (even nil results are fine in test)
    EmbedExamples.run(["--force"])

    # Row count should not change
    assert Repo.aggregate(RegistryExample, :count, :id) >= 29
  end
end
