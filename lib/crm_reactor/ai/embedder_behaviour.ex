defmodule CrmReactor.AI.EmbedderBehaviour do
  @moduledoc "Behaviour for text embedders (real and mock)."
  @callback embed(text :: String.t()) :: {:ok, [float()]} | {:error, term()}
end
