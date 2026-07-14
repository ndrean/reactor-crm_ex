defmodule CrmReactor.PromEx.AIPlugin do
  @moduledoc "PromEx plugin for AI-specific metrics: classification, NL2SQL, vision, transcription, tokens, injection."
  use PromEx.Plugin

  @impl true
  def event_metrics(_opts) do
    Event.build(
      :crm_reactor_ai_metrics,
      [
        # ── Classification ──────────────────────────────────────────────
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
          description: "Number of small -> large model escalations."
        ),

        # ── Vision ──────────────────────────────────────────────────────
        distribution(
          [:crm_reactor, :ai, :vision, :duration, :milliseconds],
          event_name: [:crm_reactor, :ai, :vision, :stop],
          measurement: :duration,
          unit: {:native, :millisecond},
          tags: [:model],
          reporter_options: [buckets: [100, 500, 1000, 5000, 15_000, 30_000]],
          description: "Vision/file classification duration."
        ),

        # ── Transcription ───────────────────────────────────────────────
        distribution(
          [:crm_reactor, :ai, :transcribe, :duration, :milliseconds],
          event_name: [:crm_reactor, :ai, :transcribe, :stop],
          measurement: :duration,
          unit: {:native, :millisecond},
          tags: [:model, :provider],
          reporter_options: [buckets: [500, 1000, 5000, 10_000, 30_000]],
          description: "Audio transcription duration."
        ),

        # ── NL2SQL ──────────────────────────────────────────────────────
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

        # ── Token usage (all models) ────────────────────────────────────
        sum(
          [:crm_reactor, :ai, :llm, :prompt_tokens, :total],
          event_name: [:crm_reactor, :ai, :llm, :tokens],
          measurement: :prompt_tokens,
          tags: [:model, :operation],
          description: "Total prompt tokens consumed."
        ),
        sum(
          [:crm_reactor, :ai, :llm, :completion_tokens, :total],
          event_name: [:crm_reactor, :ai, :llm, :tokens],
          measurement: :completion_tokens,
          tags: [:model, :operation],
          description: "Total completion tokens consumed."
        ),
        sum(
          [:crm_reactor, :ai, :llm, :total_tokens, :total],
          event_name: [:crm_reactor, :ai, :llm, :tokens],
          measurement: :total_tokens,
          tags: [:model, :operation],
          description: "Total tokens consumed (prompt + completion)."
        ),

        # ── Injection ──────────────────────────────────────────────────
        counter(
          [:crm_reactor, :ai, :injection, :blocked, :total],
          event_name: [:crm_reactor, :ai, :injection_blocked],
          description: "Number of blocked prompt injection attempts."
        )
      ]
    )
  end
end
