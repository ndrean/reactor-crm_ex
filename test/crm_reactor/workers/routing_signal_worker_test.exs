defmodule CrmReactor.Workers.RoutingSignalWorkerTest do
  use CrmReactor.DataCase, async: false
  @moduletag :cosine

  alias CrmReactor.AI.RoutingSignal
  alias CrmReactor.Repo
  alias CrmReactor.Workers.RoutingSignalWorker

  import Ecto.Query

  defp perform(args) do
    RoutingSignalWorker.perform(%Oban.Job{args: args})
  end

  test "inserts a routing_signal row with all fields" do
    args = %{
      "tenant_id" => "tenant_abc",
      "raw_input" => "Ajoute Marie",
      "cosine_workflow" => "contacts",
      "cosine_score" => 0.92,
      "pass1_workflow" => "contacts",
      "pass1_confidence" => 0.88,
      "pass2_workflow" => "contacts",
      "llm_confirmed" => true
    }

    assert :ok = perform(args)

    signal =
      Repo.one!(from s in RoutingSignal, order_by: [desc: s.id], limit: 1)

    assert signal.tenant_id == "tenant_abc"
    assert signal.raw_input == "Ajoute Marie"
    assert signal.cosine_workflow == "contacts"
    assert_in_delta signal.cosine_score, 0.92, 0.001
    assert signal.pass1_workflow == "contacts"
    assert_in_delta signal.pass1_confidence, 0.88, 0.001
    assert signal.pass2_workflow == "contacts"
    assert signal.llm_confirmed == true
    assert signal.user_corrected == nil
  end

  test "inserts a signal with nil cosine fields (no embedder available)" do
    args = %{
      "tenant_id" => "tenant_xyz",
      "raw_input" => "Quelque chose",
      "cosine_workflow" => nil,
      "cosine_score" => nil,
      "pass1_workflow" => "todos",
      "pass1_confidence" => 0.75,
      "pass2_workflow" => "todos",
      "llm_confirmed" => true
    }

    assert :ok = perform(args)

    signal =
      Repo.one!(from s in RoutingSignal, where: s.tenant_id == "tenant_xyz", limit: 1)

    assert signal.cosine_workflow == nil
    assert signal.cosine_score == nil
    assert signal.pass1_workflow == "todos"
    assert signal.llm_confirmed == true
  end

  test "returns :ok even on minimal args" do
    args = %{"tenant_id" => "t1", "raw_input" => "test"}
    assert :ok = perform(args)
  end
end
