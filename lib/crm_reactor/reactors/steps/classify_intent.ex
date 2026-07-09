defmodule CrmReactor.Reactors.Steps.ClassifyIntent do
  @moduledoc "Reactor step: validate input, then classify user intent via two-pass LLM."
  use Reactor.Step

  alias CrmReactor.AI.{
    ConversationCache,
    ExamplesCache,
    InputGuard,
    RegistryCache,
    Similarity,
    ThresholdCache
  }

  alias CrmReactor.Storage
  alias CrmReactor.Workers.RoutingSignalWorker

  require Logger

  @impl true
  def run(
        %{text: text, attachment: attachment, tenant: tenant, user_id: user_id},
        _context,
        _options
      ) do
    case InputGuard.validate(text) do
      :ok ->
        registry = RegistryCache.for_tenant(tenant.tenant_id)
        classify(text, attachment, registry, tenant.tenant_id, user_id)

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
  defp classify(text, attachment, registry, _tenant_id, _user_id) when not is_nil(attachment) do
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
  defp classify(text, nil, registry, tenant_id, user_id) do
    cosine_hints = compute_cosine_hints(text)
    context = ConversationCache.get(user_id)

    Logger.debug(
      "Cosine hints: #{inspect(Enum.map(cosine_hints, fn {w, s} -> "#{w}(#{Float.round(s, 3)})" end))}"
    )

    case classifier().classify_workflow(text, registry, cosine_hints) do
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

            fire_routing_signal(
              text,
              cosine_hints,
              pass1_workflow,
              pass1_confidence,
              pass2_workflow,
              tenant_id
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
        {top_workflow, _score} = List.first(cosine_hints, {nil, 0.0})
        classifier().classify(text, registry, top_workflow, context)
    end
  end

  defp compute_cosine_hints(text) do
    examples = ExamplesCache.all()

    case embedder().embed(text) do
      {:ok, embedding} -> Similarity.top_n_workflows(embedding, examples, 2)
      {:error, _} -> []
    end
  end

  defp scope_registry(workflow, confidence, registry) do
    threshold = ThresholdCache.get(workflow)

    if confidence >= threshold do
      scoped = Enum.filter(registry, &(&1.workflow_name == workflow))
      if scoped == [], do: registry, else: scoped
    else
      registry
    end
  end

  defp fire_routing_signal(
         text,
         cosine_hints,
         pass1_workflow,
         pass1_confidence,
         pass2_workflow,
         tenant_id
       ) do
    {cosine_workflow, cosine_score} = List.first(cosine_hints, {nil, nil})

    args = %{
      "tenant_id" => tenant_id,
      "raw_input" => text,
      "cosine_workflow" => cosine_workflow,
      "cosine_score" => cosine_score,
      "pass1_workflow" => pass1_workflow,
      "pass1_confidence" => pass1_confidence,
      "pass2_workflow" => pass2_workflow,
      "llm_confirmed" => pass1_workflow == pass2_workflow
    }

    try do
      args |> RoutingSignalWorker.new() |> Oban.insert()
    rescue
      e -> Logger.debug("Routing signal not recorded: #{inspect(e)}")
    catch
      :exit, _ -> :ok
    end

    :ok
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

  defp embedder do
    Application.get_env(:crm_reactor, :embedder, CrmReactor.AI.Embedder)
  end
end
