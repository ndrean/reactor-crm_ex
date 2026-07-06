defmodule CrmReactor.PromEx.AIPlugin do
  @moduledoc "PromEx plugin for AI-specific metrics: classification, NL2SQL, injection."
  use PromEx.Plugin

  @impl true
  def event_metrics(_opts) do
    Event.build(
      :crm_reactor_ai_metrics,
      [
        distribution(
          [:crm_reactor, :ai, :classify, :duration, :milliseconds],
          event_name: [:crm_reactor, :ai, :classify, :stop],
          measurement: :duration,
          unit: {:native, :millisecond},
          tags: [:model, :fallback],
          reporter_options: [buckets: [50, 100, 500, 1000, 5000, 15_000]],
          description: "LLM intent classification duration."
        ),
        counter(
          [:crm_reactor, :ai, :classify, :fallback, :total],
          event_name: [:crm_reactor, :ai, :classify, :fallback],
          description: "Number of Mistral -> Ollama fallbacks."
        ),
        distribution(
          [:crm_reactor, :ai, :nl2sql, :duration, :milliseconds],
          event_name: [:crm_reactor, :ai, :nl2sql, :stop],
          measurement: :duration,
          unit: {:native, :millisecond},
          tags: [:filter_count],
          reporter_options: [buckets: [50, 100, 500, 1000, 5000, 15_000]],
          description: "NL2SQL filter generation duration."
        ),
        counter(
          [:crm_reactor, :ai, :nl2sql, :fallback, :total],
          event_name: [:crm_reactor, :ai, :nl2sql, :fallback_to_deterministic],
          description: "Number of NL2SQL -> deterministic fallbacks."
        ),
        counter(
          [:crm_reactor, :ai, :injection, :blocked, :total],
          event_name: [:crm_reactor, :ai, :injection_blocked],
          description: "Number of blocked prompt injection attempts."
        )
      ]
    )
  end
end
