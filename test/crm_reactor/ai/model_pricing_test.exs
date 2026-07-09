defmodule CrmReactor.AI.ModelPricingTest do
  use ExUnit.Case, async: true

  alias CrmReactor.AI.ModelPricing

  test "all default models have pricing entries" do
    # These must match the defaults in runtime.exs and classifier.ex
    defaults = [
      {"ministral-3b-latest", "pass1_routing_legacy"},
      {"mistral-small-latest", "pass1_and_pass2_classification"},
      {"codestral-latest", "pass2_escalation"},
      {"ministral-3b-2512", "vision_attachment"},
      {"mistral-large-latest", "example_review_judge"},
      {"qwen2.5:7b", "local_fallback"},
      {"mxbai-embed-large", "embedding"}
    ]

    for {model, role} <- defaults do
      assert ModelPricing.get(model),
             "Model #{inspect(model)} (#{role}) not found in model_pricing.json"
    end
  end

  test "all pricing entries have a matching role" do
    for {model, entry} <- ModelPricing.all() do
      assert entry["role"],
             "Model #{inspect(model)} is missing a role in model_pricing.json"
    end
  end

  test "cost/3 computes correctly" do
    assert {:ok, cost} = ModelPricing.cost("mistral-small-latest", 1000, 100)
    # 1000 * 0.15/1M + 100 * 0.60/1M = 0.00015 + 0.00006 = 0.00021
    assert_in_delta cost, 0.00021, 0.000001
  end

  test "cost/3 returns error for unknown model" do
    assert {:error, :unknown_model} = ModelPricing.cost("nonexistent-model", 100, 100)
  end

  test "two_pass_cost/6 sums both passes" do
    assert {:ok, total} =
             ModelPricing.two_pass_cost(
               "ministral-3b-latest",
               200,
               20,
               "mistral-small-latest",
               1000,
               30
             )

    {:ok, p1} = ModelPricing.cost("ministral-3b-latest", 200, 20)
    {:ok, p2} = ModelPricing.cost("mistral-small-latest", 1000, 30)
    assert_in_delta total, p1 + p2, 0.000001
  end

  test "ollama models have zero cost" do
    assert {:ok, cost1} = ModelPricing.cost("qwen2.5:7b", 10_000, 5_000)
    assert cost1 == 0.0
    assert {:ok, cost2} = ModelPricing.cost("mxbai-embed-large", 10_000, 0)
    assert cost2 == 0.0
  end
end
