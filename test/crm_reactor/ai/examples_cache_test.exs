defmodule CrmReactor.AI.ExamplesCacheTest do
  use CrmReactor.DataCase, async: false

  alias CrmReactor.AI.ExamplesCache
  alias CrmReactor.Repo
  alias CrmReactor.Tenants.RegistryExample

  setup do
    # Ensure the cache starts clean for each test
    ExamplesCache.reload()

    on_exit(fn ->
      # Clear ETS after each test so leaked entries don't affect other test modules
      ExamplesCache.reload()
    end)

    :ok
  end

  defp insert_example(workflow, phrase) do
    Repo.insert!(%RegistryExample{
      workflow_name: workflow,
      phrase: phrase,
      inserted_at: DateTime.utc_now() |> DateTime.truncate(:second)
    })
  end

  test "all/0 returns [] when table has no examples" do
    ExamplesCache.reload()
    assert ExamplesCache.all() == []
  end

  test "all/0 returns examples after reload" do
    insert_example("contacts", "Ajoute un contact")
    insert_example("todos", "Rappelle-moi demain")

    ExamplesCache.reload()

    entries = ExamplesCache.all()
    assert length(entries) == 2
    workflows = Enum.map(entries, & &1.workflow_name)
    assert "contacts" in workflows
    assert "todos" in workflows
  end

  test "all/0 returns examples with embeddings when set" do
    embedding = Enum.map(1..4, fn i -> i * 0.1 end)

    Repo.insert!(%RegistryExample{
      workflow_name: "contacts",
      phrase: "Phrase test",
      embedding: embedding,
      inserted_at: DateTime.utc_now() |> DateTime.truncate(:second)
    })

    ExamplesCache.reload()

    [entry] = ExamplesCache.all()
    assert entry.embedding == embedding
  end
end
