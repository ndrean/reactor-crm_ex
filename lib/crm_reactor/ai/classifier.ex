defmodule CrmReactor.AI.Classifier do
  @moduledoc "Intent classification via Mistral Small with Ollama fallback."
  @behaviour CrmReactor.AI.ClassifierBehaviour

  alias CrmReactor.AI.{Prompts, Telemetry}

  require Logger

  @impl true
  def classify_workflow(text, registry_entries, cosine_hints) do
    system_prompt = Prompts.build_pass1_prompt(registry_entries, cosine_hints)
    model = Application.get_env(:crm_reactor, :mistral_model_small, "mistral-small-latest")
    api_key = Application.fetch_env!(:crm_reactor, :mistral_api_key)

    case Req.post("https://api.mistral.ai/v1/chat/completions",
           json: %{
             model: model,
             messages: [
               %{role: "system", content: system_prompt},
               %{role: "user", content: text}
             ],
             response_format: %{type: "json_object"},
             temperature: 0
           },
           headers: [{"authorization", "Bearer #{api_key}"}],
           receive_timeout: 10_000
         ) do
      {:ok, %{status: 200, body: body}} ->
        parse_pass1_response(body)

      {:ok, %{status: status, body: body}} ->
        Logger.warning("Mistral Pass 1 error #{status}: #{inspect(body)}")
        {:error, "Mistral Pass 1 error #{status}"}

      {:error, reason} ->
        Logger.warning("Mistral Pass 1 request failed: #{inspect(reason)}")
        {:error, "Mistral Pass 1 request failed: #{inspect(reason)}"}
    end
  end

  defp parse_pass1_response(body) do
    [choice | _] = body["choices"]
    usage = body["usage"]

    case Jason.decode(choice["message"]["content"]) do
      {:ok, %{"workflow" => w, "confidence" => c}} when is_binary(w) and is_number(c) ->
        # LLM sometimes returns "contacts: list" instead of "contacts" — strip action part
        workflow = w |> String.split(~r/[:\s]/, parts: 2) |> List.first()

        pass1_usage = %{
          prompt_tokens: usage["prompt_tokens"] || 0,
          completion_tokens: usage["completion_tokens"] || 0,
          total_tokens: usage["total_tokens"] || 0
        }

        {:ok, {workflow, c, pass1_usage}}

      {:ok, other} ->
        Logger.warning("Unexpected Pass 1 response shape: #{inspect(other)}")
        {:error, :unexpected_pass1_response}

      {:error, reason} ->
        Logger.warning("Pass 1 JSON decode error: #{inspect(reason)}")
        {:error, :pass1_json_decode_error}
    end
  end

  @impl true
  def classify_with_file(instruction, file_content, content_type, registry_entries) do
    system_prompt = Prompts.build_vision_prompt(registry_entries)
    model = Application.get_env(:crm_reactor, :mistral_vision_model, "ministral-3b-2512")
    api_key = Application.fetch_env!(:crm_reactor, :mistral_api_key)

    case Req.post("https://api.mistral.ai/v1/chat/completions",
           json: %{
             model: model,
             messages: [
               %{role: "system", content: system_prompt},
               %{
                 role: "user",
                 content: build_file_message(instruction, file_content, content_type)
               }
             ],
             response_format: %{type: "json_object"},
             temperature: 0
           },
           headers: [{"authorization", "Bearer #{api_key}"}],
           receive_timeout: 30_000
         ) do
      {:ok, %{status: 200, body: body}} ->
        parse_llm_response(body)

      {:ok, %{status: status, body: body}} ->
        Logger.warning("Mistral vision error #{status}: #{inspect(body)}")
        {:error, "Mistral vision error #{status}"}

      {:error, reason} ->
        Logger.warning("Mistral vision request failed: #{inspect(reason)}")
        {:error, "Mistral vision request failed: #{inspect(reason)}"}
    end
  end

  @impl true
  def classify(text, registry_entries), do: classify(text, registry_entries, nil)

  @impl true
  def classify(text, registry_entries, routing_hint),
    do: classify(text, registry_entries, routing_hint, [])

  @impl true
  def classify(text, registry_entries, routing_hint, context) do
    system_prompt = Prompts.build_master_prompt(registry_entries, routing_hint, context)
    start_time = Telemetry.classify_start()

    model_small = Application.get_env(:crm_reactor, :mistral_model_small, "mistral-small-latest")
    model_large = Application.get_env(:crm_reactor, :mistral_model_large, "codestral-latest")

    case classify_mistral(text, system_prompt, model_small) do
      {:ok, %{steps: [%{workflow: "none"}]}} ->
        Logger.info("#{model_small} returned 'none', escalating to #{model_large}")
        Telemetry.classify_fallback(%{reason: "small_no_match"})

        case classify_mistral(text, system_prompt, model_large) do
          {:ok, _} = result ->
            Telemetry.classify_stop(start_time, %{model: model_large, fallback: true})
            result

          {:error, reason} ->
            Logger.warning("#{model_large} failed: #{inspect(reason)}, falling back to Ollama")
            result = classify_ollama(text, system_prompt)
            Telemetry.classify_stop(start_time, %{model: "ollama", fallback: true})
            result
        end

      {:ok, _} = result ->
        Telemetry.classify_stop(start_time, %{model: model_small, fallback: false})
        result

      {:error, reason} ->
        Logger.warning("#{model_small} failed: #{inspect(reason)}, falling back to Ollama")
        Telemetry.classify_fallback(%{reason: inspect(reason)})
        result = classify_ollama(text, system_prompt)
        Telemetry.classify_stop(start_time, %{model: "ollama", fallback: true})
        result
    end
  end

  defp classify_mistral(text, system_prompt, model) do
    api_key = Application.fetch_env!(:crm_reactor, :mistral_api_key)

    case Req.post("https://api.mistral.ai/v1/chat/completions",
           json: %{
             model: model,
             messages: [
               %{role: "system", content: system_prompt},
               %{role: "user", content: text}
             ],
             response_format: %{type: "json_object"},
             temperature: 0
           },
           headers: [{"authorization", "Bearer #{api_key}"}],
           receive_timeout: 15_000
         ) do
      {:ok, %{status: 200, body: body}} ->
        parse_llm_response(body)

      {:ok, %{status: status, body: body}} ->
        {:error, "Mistral API error #{status}: #{inspect(body)}"}

      {:error, reason} ->
        {:error, "Mistral request failed: #{inspect(reason)}"}
    end
  end

  defp classify_ollama(text, system_prompt) do
    ollama_url =
      Application.get_env(:crm_reactor, :ollama_url, "http://127.0.0.1:11435")

    model = Application.get_env(:crm_reactor, :ollama_model, "qwen2.5:7b")

    case Req.post("#{ollama_url}/api/chat",
           json: %{
             model: model,
             messages: [
               %{role: "system", content: system_prompt},
               %{role: "user", content: text}
             ],
             format: "json",
             stream: false
           },
           receive_timeout: 30_000
         ) do
      {:ok, %{status: 200, body: body}} ->
        content = body["message"]["content"]

        case Jason.decode(content) do
          {:ok, parsed} ->
            {:ok,
             %{
               steps: parse_steps(parsed),
               prompt_tokens: 0,
               completion_tokens: 0,
               total_tokens: 0
             }}

          {:error, reason} ->
            Logger.warning("Ollama JSON decode error: #{inspect(reason)}")
            {:error, :ollama_json_decode_error}
        end

      {:ok, %{status: status, body: body}} ->
        {:error, "Ollama error #{status}: #{inspect(body)}"}

      {:error, reason} ->
        {:error, "Ollama request failed: #{inspect(reason)}"}
    end
  end

  defp parse_llm_response(body) do
    [choice | _] = body["choices"]
    usage = body["usage"]

    case Jason.decode(choice["message"]["content"]) do
      {:ok, parsed} ->
        {:ok,
         %{
           steps: parse_steps(parsed),
           prompt_tokens: usage["prompt_tokens"],
           completion_tokens: usage["completion_tokens"],
           total_tokens: usage["total_tokens"]
         }}

      {:error, reason} ->
        Logger.warning("LLM JSON decode error: #{inspect(reason)}")
        {:error, :llm_json_decode_error}
    end
  end

  # New format: {"steps": [...]}
  defp parse_steps(%{"steps" => steps}) when is_list(steps) and steps != [] do
    Enum.map(steps, &parse_step/1)
  end

  # Fallback: old single-object format or malformed — wrap in list
  defp parse_steps(intent) do
    [parse_step(intent)]
  end

  defp parse_step(s) do
    %{
      id: s["id"] || generate_step_id(),
      workflow: s["workflow"] || "none",
      action: s["action"] || "none",
      params: s["params"] || %{},
      routing_path: s["routing_path"] || "deterministic",
      depends_on: s["depends_on"] || [],
      for_each: s["for_each"],
      map_param: s["map_param"]
    }
  end

  defp generate_step_id, do: "step_#{:erlang.unique_integer([:positive, :monotonic])}"

  @image_types ~w(image/jpeg image/jpg image/png image/gif image/webp)

  defp build_file_message(instruction, content, content_type) when content_type in @image_types do
    base64 = Base.encode64(content)

    [
      %{type: "text", text: instruction},
      %{type: "image_url", image_url: %{url: "data:#{content_type};base64,#{base64}"}}
    ]
  end

  defp build_file_message(instruction, content, _content_type) do
    "#{instruction}\n\nFile content:\n#{content}"
  end
end
