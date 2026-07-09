defmodule CrmReactor.AI.ThresholdCacheTest do
  use CrmReactor.DataCase, async: false

  alias CrmReactor.AI.{RoutingThreshold, ThresholdCache}
  alias CrmReactor.Repo

  setup do
    ThresholdCache.reload()
    :ok
  end

  defp insert_threshold(workflow, threshold) do
    Repo.insert!(
      %RoutingThreshold{
        workflow_name: workflow,
        threshold: threshold,
        sample_count: 10,
        calibrated_at: DateTime.utc_now() |> DateTime.truncate(:second)
      },
      on_conflict: [set: [threshold: threshold, sample_count: 10]],
      conflict_target: :workflow_name,
      prefix: "global_registry"
    )
  end

  test "get/1 returns 0.70 default for unknown workflow" do
    assert ThresholdCache.get("unknown_workflow") == 0.70
  end

  test "get/1 returns configured threshold after reload" do
    insert_threshold("contacts", 0.85)

    ThresholdCache.reload()

    assert ThresholdCache.get("contacts") == 0.85
  end

  test "get/1 returns default 0.70 when no row exists for workflow" do
    # The migration seeds contacts/todos/data/help, but here we're testing an unknown name
    assert ThresholdCache.get("nonexistent_workflow") == 0.70
  end

  test "get/1 returns updated value after second reload" do
    insert_threshold("todos", 0.75)
    ThresholdCache.reload()
    assert ThresholdCache.get("todos") == 0.75

    insert_threshold("todos", 0.90)
    ThresholdCache.reload()
    assert ThresholdCache.get("todos") == 0.90
  end
end
