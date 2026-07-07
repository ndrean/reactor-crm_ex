defmodule CrmReactor.Reactors.Steps.ClassifyIntent do
  @moduledoc "Reactor step: validate input, then classify user intent via LLM."
  use Reactor.Step

  alias CrmReactor.AI.{InputGuard, RegistryCache}
  alias CrmReactor.Storage

  require Logger

  @impl true
  def run(%{text: text, attachment: attachment, tenant: tenant}, _context, _options) do
    case InputGuard.validate(text) do
      :ok ->
        registry = RegistryCache.for_tenant(tenant.tenant_id)
        classify(text, attachment, registry)

      {:rejected, message} ->
        {:ok,
         %{
           steps: [
             %{workflow: "none", action: "none", params: %{}, routing_path: "deterministic"}
           ],
           prompt_tokens: 0,
           completion_tokens: 0,
           total_tokens: 0,
           rejected: message
         }}
    end
  end

  defp classify(text, nil, registry), do: classifier().classify(text, registry)

  defp classify(text, attachment, registry) do
    case Storage.get(attachment.storage_key) do
      {:ok, file_content} ->
        case classifier().classify_with_file(
               text,
               file_content,
               attachment.content_type,
               registry
             ) do
          {:ok, _} = ok ->
            ok

          {:error, reason} ->
            Logger.warning(
              "Vision classification failed (#{inspect(reason)}), falling back to text-only"
            )

            classifier().classify(text, registry)
        end

      {:error, reason} ->
        Logger.warning("Failed to fetch attachment for classification: #{inspect(reason)}")
        classifier().classify(text, registry)
    end
  end

  defp classifier do
    Application.get_env(:crm_reactor, :classifier, CrmReactor.AI.Classifier)
  end
end
