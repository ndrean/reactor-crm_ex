defmodule CrmReactor.AI.ClassifierTest do
  use CrmReactor.DataCase

  alias CrmReactor.AI.Classifier
  alias CrmReactor.Tenants.ModuleRegistry

  @moduletag :external

  setup do
    registry = Repo.all(ModuleRegistry)
    %{registry: registry}
  end

  @tag :requires_mistral
  test "classifies contact search", %{registry: registry} do
    {:ok, result} = Classifier.classify("cherche Marie Dupont", registry)
    [step] = result.steps
    assert step.workflow == "contacts"
    assert step.action == "search"
    search_val = step.params["search_name"] || step.params["name"] || step.params["query"]
    assert search_val =~ "Marie"
    assert result.total_tokens > 0
  end

  @tag :requires_mistral
  test "classifies todo creation", %{registry: registry} do
    {:ok, result} = Classifier.classify("crée une tâche appeler le client demain", registry)
    [step] = result.steps
    assert step.workflow == "todos"
    assert step.action == "create"
    assert Enum.any?(["subject", "title"], &is_binary(step.params[&1]))
  end

  test "classifies contact count", %{registry: registry} do
    {:ok, result} = Classifier.classify("combien de contacts ai-je", registry)
    [step] = result.steps
    assert step.workflow == "contacts"
    assert step.action == "count"
  end

  test "classifies data export", %{registry: registry} do
    {:ok, result} = Classifier.classify("exporte mes données d'utilisation", registry)
    [step] = result.steps
    assert step.workflow == "data"
    assert step.action == "dump"
  end

  test "returns none for gibberish", %{registry: registry} do
    {:ok, result} = Classifier.classify("blablabla asdfgh", registry)
    [step] = result.steps
    assert step.workflow == "none"
  end

  @tag :requires_mistral
  test "classify_workflow/3 returns workflow name, confidence, and usage", %{registry: registry} do
    {:ok, {workflow, confidence, usage}} =
      Classifier.classify_workflow("ajoute un contact Marie", registry, [])

    assert byte_size(workflow) > 0
    assert is_float(confidence)
    assert confidence >= 0.0 and confidence <= 1.0
    assert workflow == "contacts"
    assert usage.prompt_tokens > 0
    assert usage.completion_tokens > 0
  end

  @tag :requires_mistral
  test "classify_workflow/3 returns none for gibberish", %{registry: registry} do
    {:ok, {workflow, confidence, _usage}} =
      Classifier.classify_workflow("blablabla asdfgh", registry, [])

    assert workflow == "none"
    assert is_float(confidence)
  end

  @tag :requires_mistral
  test "escalation: codestral handles what mistral-small returns none for", %{registry: registry} do
    # "que puis-je faire ici ?" is ambiguous enough that small may return "none",
    # triggering escalation to codestral-latest
    {:ok, result} = Classifier.classify("que puis-je faire ici ?", registry)
    [step | _] = result.steps
    # Either model should route this to "help"
    assert step.workflow == "help"
    assert result.total_tokens > 0
  end
end
