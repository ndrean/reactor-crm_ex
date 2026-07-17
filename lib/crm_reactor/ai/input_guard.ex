defmodule CrmReactor.AI.InputGuard do
  @moduledoc """
  Input guard. Rejects user input containing SQL injection patterns before
  it reaches the NL2SQL path. Prompt injection defense is handled by the
  LLM system prompt (not regex).
  """

  require Logger

  @sql_patterns [
    ~r/\bDROP\s+TABLE\b/i,
    ~r/\bDROP\s+SCHEMA\b/i,
    ~r/\bDELETE\s+FROM\b/i,
    ~r/\bUPDATE\s+[^;]*\bSET\b/i,
    ~r/\bINSERT\s+INTO\b/i,
    ~r/\bTRUNCATE\b/i,
    ~r/;\s*(DROP|DELETE|UPDATE|INSERT|ALTER|GRANT)/i,
    ~r/\bpg_(catalog|shadow|roles|user|tables|stat|settings|authid|database)\b/i,
    ~r/information_schema/i,
    ~r/\bUNION\s+(ALL\s+)?SELECT\b/i
  ]

  @max_input_bytes 4_096

  @spec validate(String.t()) :: :ok | {:rejected, String.t()}
  def validate(text) when byte_size(text) > @max_input_bytes do
    Logger.warning("Input rejected: #{byte_size(text)} bytes exceeds #{@max_input_bytes} limit")
    :telemetry.execute([:crm_reactor, :ai, :injection_blocked], %{count: 1}, %{})
    {:rejected, "Requête non autorisée."}
  end

  def validate(text) do
    case Enum.find(@sql_patterns, &Regex.match?(&1, text)) do
      nil ->
        :ok

      pattern ->
        Logger.warning(
          "SQL injection blocked: #{inspect(pattern)} matched in: #{String.slice(text, 0, 100)}"
        )

        :telemetry.execute([:crm_reactor, :ai, :injection_blocked], %{count: 1}, %{})
        {:rejected, "Requête non autorisée."}
    end
  end
end
