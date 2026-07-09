defmodule CrmReactor.MockEmbedder do
  @moduledoc "Mock embedder for tests — returns error so no hint is computed and Nx is never called."
  @behaviour CrmReactor.AI.EmbedderBehaviour

  @impl true
  def embed(_text), do: {:error, :not_configured}
end
