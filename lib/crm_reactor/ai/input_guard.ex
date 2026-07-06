defmodule CrmReactor.AI.InputGuard do
  @moduledoc """
  Prompt injection guard. Rejects user input containing known attack
  patterns before it reaches the LLM. Defense in depth — the system
  prompt should also resist injection, but this avoids wasting an API
  call and logs the attempt.
  """

  require Logger

  @injection_patterns [
    ~r/ignore\s+(all\s+)?(previous|prior|above)\s+(instructions|prompts|rules)/i,
    ~r/disregard\s+(your|all|the)\s+(instructions|rules|prompt)/i,
    ~r/you\s+are\s+now\s+(a|an|in)\s/i,
    ~r/system\s*:\s/i,
    ~r/\bDROP\s+TABLE\b/i,
    ~r/\bDROP\s+SCHEMA\b/i,
    ~r/\bDELETE\s+FROM\b/i,
    ~r/\bUPDATE\s+.*\bSET\b/i,
    ~r/\bINSERT\s+INTO\b/i,
    ~r/\bTRUNCATE\b/i,
    ~r/;\s*(DROP|DELETE|UPDATE|INSERT|ALTER|GRANT)/i,
    ~r/pg_\w+/i,
    ~r/information_schema/i,
    ~r/\bUNION\s+(ALL\s+)?SELECT\b/i
  ]

  @spec validate(String.t()) :: :ok | {:rejected, String.t()}
  def validate(text) do
    case Enum.find(@injection_patterns, &Regex.match?(&1, text)) do
      nil ->
        :ok

      pattern ->
        Logger.warning(
          "Prompt injection blocked: #{inspect(pattern)} matched in: #{String.slice(text, 0, 100)}"
        )

        :telemetry.execute([:crm_reactor, :ai, :injection_blocked], %{count: 1}, %{})
        {:rejected, "Requête non autorisée."}
    end
  end
end
