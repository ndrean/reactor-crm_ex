defmodule CrmReactor.AI.Embedder do
  @moduledoc "Calls Ollama embed API to produce a 1024-dim vector for a text string."
  @behaviour CrmReactor.AI.EmbedderBehaviour

  require Logger

  @impl true
  def embed(text) when is_binary(text) do
    url = "#{ollama_url()}/api/embed"
    model = Application.get_env(:crm_reactor, :embedding_model, "mxbai-embed-large")

    case Req.post(url, json: %{model: model, input: text}, receive_timeout: 10_000) do
      {:ok, %{status: 200, body: %{"embeddings" => [embedding | _]}}} when is_list(embedding) ->
        {:ok, embedding}

      {:ok, %{status: 200, body: body}} ->
        Logger.warning("Ollama embed unexpected response shape: #{inspect(body)}")
        {:error, :unexpected_response}

      {:ok, %{status: status, body: body}} ->
        Logger.warning("Ollama embed error #{status}: #{inspect(body)}")
        {:error, "Ollama embed error #{status}"}

      {:error, reason} ->
        Logger.warning("Ollama embed request failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp ollama_url do
    Application.get_env(:crm_reactor, :ollama_url, "http://127.0.0.1:11435")
  end
end
