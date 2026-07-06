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
    assert step.params["subject"] || step.params["title"]
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
end
