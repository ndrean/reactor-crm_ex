defmodule CrmReactor.AI.Telemetry do
  @moduledoc "Emits telemetry events for AI operations."

  def classify_start do
    :telemetry.execute(
      [:crm_reactor, :ai, :classify, :start],
      %{system_time: System.system_time()},
      %{}
    )

    System.monotonic_time()
  end

  def classify_stop(start_time, metadata) do
    duration = System.monotonic_time() - start_time

    :telemetry.execute(
      [:crm_reactor, :ai, :classify, :stop],
      %{duration: duration},
      metadata
    )
  end

  def classify_fallback(metadata) do
    :telemetry.execute(
      [:crm_reactor, :ai, :classify, :fallback],
      %{count: 1},
      metadata
    )
  end

  def nl2sql_stop(start_time, metadata) do
    duration = System.monotonic_time() - start_time

    :telemetry.execute(
      [:crm_reactor, :ai, :nl2sql, :stop],
      %{duration: duration},
      metadata
    )
  end

  def nl2sql_fallback_to_deterministic(metadata) do
    :telemetry.execute(
      [:crm_reactor, :ai, :nl2sql, :fallback_to_deterministic],
      %{count: 1},
      metadata
    )
  end
end
