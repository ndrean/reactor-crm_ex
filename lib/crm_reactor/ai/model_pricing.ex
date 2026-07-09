defmodule CrmReactor.AI.ModelPricing do
  @moduledoc """
  Reads model pricing from `priv/ai/model_pricing.json` at compile time.
  Provides cost estimation per model based on token counts.
  """

  @pricing_path "priv/ai/model_pricing.json"
  @external_resource @pricing_path

  @pricing @pricing_path
           |> File.read!()
           |> Jason.decode!()
           |> Map.get("models")

  @doc "Returns the pricing map for a model, or nil if unknown."
  def get(model), do: Map.get(@pricing, model)

  @doc "Returns all model pricing entries."
  def all, do: @pricing

  @doc """
  Computes cost in USD for a given model and token counts.
  Returns `{:ok, float}` or `{:error, :unknown_model}`.
  """
  def cost(model, prompt_tokens, completion_tokens) do
    case get(model) do
      nil ->
        {:error, :unknown_model}

      pricing ->
        input_cost = prompt_tokens * pricing["input_per_million"] / 1_000_000
        output_cost = completion_tokens * pricing["output_per_million"] / 1_000_000
        {:ok, input_cost + output_cost}
    end
  end

  @doc """
  Estimates total cost for a two-pass classification request.
  Pass 1 model + Pass 2 model token counts → combined USD cost.
  """
  def two_pass_cost(pass1_model, p1_prompt, p1_completion, pass2_model, p2_prompt, p2_completion) do
    with {:ok, c1} <- cost(pass1_model, p1_prompt, p1_completion),
         {:ok, c2} <- cost(pass2_model, p2_prompt, p2_completion) do
      {:ok, c1 + c2}
    end
  end
end
