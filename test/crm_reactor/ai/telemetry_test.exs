defmodule CrmReactor.AI.TelemetryTest do
  use ExUnit.Case, async: true

  alias CrmReactor.AI.Telemetry

  test "classify_start returns a monotonic integer" do
    t = Telemetry.classify_start()
    assert is_integer(t)
  end

  test "classify_stop does not raise" do
    t = Telemetry.classify_start()
    Telemetry.classify_stop(t, %{model: "test-model"})
  end

  test "classify_fallback does not raise" do
    Telemetry.classify_fallback(%{model: "test-model", reason: "timeout"})
  end

  test "nl2sql_stop does not raise" do
    t = System.monotonic_time()
    Telemetry.nl2sql_stop(t, %{module: "contacts"})
  end

  test "nl2sql_fallback_to_deterministic does not raise" do
    Telemetry.nl2sql_fallback_to_deterministic(%{module: "todos"})
  end
end
