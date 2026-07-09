defmodule CrmReactor.Workers.ThresholdCalibrationWorkerTest do
  use CrmReactor.DataCase, async: false

  alias CrmReactor.AI.{RoutingSignal, RoutingThreshold, ThresholdCache}
  alias CrmReactor.Repo
  alias CrmReactor.Workers.ThresholdCalibrationWorker

  # import Ecto.Query

  defp insert_signal(workflow, confidence, confirmed \\ true) do
    Repo.insert!(%RoutingSignal{
      tenant_id: "tenant_test",
      raw_input: "test input",
      pass1_workflow: workflow,
      pass1_confidence: confidence,
      pass2_workflow: workflow,
      llm_confirmed: confirmed,
      inserted_at: DateTime.utc_now() |> DateTime.truncate(:second)
    })
  end

  test "updates threshold based on confirmed signals" do
    # avg(0.90, 0.80, 0.85) = 0.85; * 0.85 safety margin = 0.7225
    insert_signal("contacts", 0.90)
    insert_signal("contacts", 0.80)
    insert_signal("contacts", 0.85)

    assert :ok = ThresholdCalibrationWorker.perform(%Oban.Job{args: %{}})

    row = Repo.get(RoutingThreshold, "contacts")
    assert row != nil
    assert_in_delta row.threshold, 0.85 * 0.85, 0.001
    assert row.sample_count == 3
  end

  test "ignores unconfirmed signals" do
    insert_signal("todos", 0.99, false)

    # Run calibration — todos row should NOT be updated (no confirmed signals)
    assert :ok = ThresholdCalibrationWorker.perform(%Oban.Job{args: %{}})

    # todos row from migration stays at 0.70 (if seeded) or doesn't exist
    row = Repo.get(RoutingThreshold, "todos")

    # Either the row is unchanged (0.70 from seed) or absent — not calibrated to 0.99
    if row != nil do
      assert abs(row.threshold - 0.99 * 0.85) > 0.001
    end
  end

  test "reloads ThresholdCache after calibration" do
    insert_signal("data", 1.0)
    insert_signal("data", 1.0)

    assert :ok = ThresholdCalibrationWorker.perform(%Oban.Job{args: %{}})

    # 1.0 * 0.85 = 0.85
    assert_in_delta ThresholdCache.get("data"), 0.85, 0.001
  end

  test "handles empty signals table without error" do
    assert :ok = ThresholdCalibrationWorker.perform(%Oban.Job{args: %{}})
  end
end
