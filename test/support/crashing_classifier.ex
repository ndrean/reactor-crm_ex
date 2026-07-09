defmodule CrmReactor.AI.CrashingClassifier do
  @moduledoc "Classifier that always fails, for testing error recovery."
  @behaviour CrmReactor.AI.ClassifierBehaviour

  @impl true
  def classify_workflow(_text, _registry, _hints) do
    {:error, "LLM unavailable (test crash)"}
  end

  @impl true
  def classify_with_file(_instruction, _file_content, _content_type, _registry) do
    {:error, "LLM unavailable (test crash)"}
  end

  @impl true
  def classify(_text, _registry, _routing_hint) do
    {:error, "LLM unavailable (test crash)"}
  end

  @impl true
  def classify(_text, _registry, _routing_hint, _context) do
    {:error, "LLM unavailable (test crash)"}
  end

  @impl true
  def classify(_text, _registry) do
    {:error, "LLM unavailable (test crash)"}
  end
end
