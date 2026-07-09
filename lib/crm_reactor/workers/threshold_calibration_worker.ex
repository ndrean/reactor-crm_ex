defmodule CrmReactor.Workers.ThresholdCalibrationWorker do
  @moduledoc """
  Oban cron worker: recalibrates per-workflow confidence thresholds from routing signals.

  Formula: new_threshold = avg(pass1_confidence | llm_confirmed, last 30 days) * 0.85
  (10% safety margin below the observed average confirmed confidence).
  Workflows with no confirmed signals in the window keep their existing threshold.
  """
  use Oban.Worker, queue: :maintenance, max_attempts: 1

  alias CrmReactor.AI.{RoutingSignal, RoutingThreshold, ThresholdCache}
  alias CrmReactor.Repo

  import Ecto.Query

  @window_days 30
  @safety_margin 0.85

  @impl true
  def perform(_job) do
    cutoff = DateTime.add(DateTime.utc_now(), -@window_days * 86_400, :second)

    signals =
      Repo.all(
        from s in RoutingSignal,
          where:
            s.llm_confirmed == true and
              not is_nil(s.pass1_workflow) and
              not is_nil(s.pass1_confidence) and
              s.inserted_at >= ^cutoff,
          select: {s.pass1_workflow, s.pass1_confidence}
      )

    signals
    |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
    |> Enum.each(fn {workflow, confidences} ->
      avg = Enum.sum(confidences) / length(confidences)
      new_threshold = avg * @safety_margin
      sample_count = length(confidences)

      Repo.insert(
        %RoutingThreshold{
          workflow_name: workflow,
          threshold: new_threshold,
          sample_count: sample_count,
          calibrated_at: DateTime.utc_now() |> DateTime.truncate(:second)
        },
        on_conflict: [
          set: [
            threshold: new_threshold,
            sample_count: sample_count,
            calibrated_at: DateTime.utc_now() |> DateTime.truncate(:second)
          ]
        ],
        conflict_target: :workflow_name,
        prefix: "global_registry"
      )
    end)

    ThresholdCache.reload()
    :ok
  end
end
