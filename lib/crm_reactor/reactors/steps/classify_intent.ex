defmodule CrmReactor.Reactors.Steps.ClassifyIntent do
  @moduledoc "Reactor step: validate input, then classify user intent via two-pass LLM."
  use Reactor.Step

  alias CrmReactor.AI.{ConversationCache, InputGuard, RegistryCache}
  alias CrmReactor.Storage

  require Logger

  @default_threshold 0.70

  @impl true
  def run(
        %{text: text, attachment: attachment, tenant: tenant, user_id: user_id},
        _context,
        _options
      ) do
    case InputGuard.validate(text) do
      :ok ->
        registry = RegistryCache.for_tenant(tenant.tenant_id)
        classify(text, attachment, registry, user_id)

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

  # File attachment: skip two-pass, go directly to vision classifier
  defp classify(text, attachment, registry, _user_id) when not is_nil(attachment) do
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

            classifier().classify(text, registry, nil)
        end

      {:error, reason} ->
        Logger.warning("Failed to fetch attachment for classification: #{inspect(reason)}")
        classifier().classify(text, registry, nil)
    end
  end

  # Text-only: two-pass orchestration
  defp classify(text, nil, registry, user_id) do
    context = ConversationCache.get(user_id)

    case classifier().classify_workflow(text, registry, []) do
      {:ok, {pass1_workflow, pass1_confidence, pass1_usage}} ->
        scoped_registry = scope_registry(pass1_workflow, pass1_confidence, registry)
        routing_hint = if pass1_workflow != "none", do: pass1_workflow, else: nil

        Logger.debug(
          "Pass 1: #{pass1_workflow} (#{Float.round(pass1_confidence, 3)}), " <>
            "scoped to #{length(scoped_registry)} of #{length(registry)} actions | " <>
            "P1 in=#{pass1_usage.prompt_tokens} out=#{pass1_usage.completion_tokens}"
        )

        case classifier().classify(text, scoped_registry, routing_hint, context) do
          {:ok, result} ->
            pass2_workflow =
              result.steps |> List.first(%{}) |> Map.get(:workflow)

            Logger.debug(
              "Pass 2: #{pass2_workflow} | " <>
                "P2 in=#{result[:prompt_tokens]} out=#{result[:completion_tokens]} | " <>
                "total=#{(pass1_usage.total_tokens || 0) + (result[:total_tokens] || 0)}"
            )

            {:ok, sum_usage(result, pass1_usage)}

          {:error, reason} ->
            Logger.warning("Pass 2 failed: #{inspect(reason)}, retrying with full registry")

            with {:ok, result} <- classifier().classify(text, registry, routing_hint, context) do
              {:ok, sum_usage(result, pass1_usage)}
            end
        end

      {:error, reason} ->
        Logger.warning("Pass 1 failed: #{inspect(reason)}, falling back to single-pass")
        classifier().classify(text, registry, nil, context)
    end
  end

  defp scope_registry(workflow, confidence, registry) do
    if confidence >= @default_threshold do
      scoped = Enum.filter(registry, &(&1.workflow_name == workflow))
      if scoped == [], do: registry, else: scoped
    else
      registry
    end
  end

  defp sum_usage(result, pass1_usage) do
    %{
      result
      | prompt_tokens: (result[:prompt_tokens] || 0) + pass1_usage.prompt_tokens,
        completion_tokens: (result[:completion_tokens] || 0) + pass1_usage.completion_tokens,
        total_tokens: (result[:total_tokens] || 0) + pass1_usage.total_tokens
    }
  end

  defp classifier do
    Application.get_env(:crm_reactor, :classifier, CrmReactor.AI.Classifier)
  end
end
