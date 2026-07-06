defmodule CrmReactor.AI.Classifier do
  @moduledoc "Intent classification via Mistral Small with Ollama fallback."
  @behaviour CrmReactor.AI.ClassifierBehaviour

  alias CrmReactor.AI.{Prompts, Telemetry}

  require Logger

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
  def classify(text, registry_entries) do
    system_prompt = Prompts.build_master_prompt(registry_entries)
    start_time = Telemetry.classify_start()

    model_small = Application.get_env(:crm_reactor, :mistral_model_small, "mistral-small-latest")
    model_large = Application.get_env(:crm_reactor, :mistral_model_large, "mistral-medium-latest")

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
      Application.get_env(:crm_reactor, :ollama_url, "http://host.docker.internal:11434")

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
        parsed = Jason.decode!(content)

        {:ok,
         %{
           steps: parse_steps(parsed),
           prompt_tokens: 0,
           completion_tokens: 0,
           total_tokens: 0
         }}

      {:ok, %{status: status, body: body}} ->
        {:error, "Ollama error #{status}: #{inspect(body)}"}

      {:error, reason} ->
        {:error, "Ollama request failed: #{inspect(reason)}"}
    end
  end

  defp parse_llm_response(body) do
    [choice | _] = body["choices"]
    parsed = Jason.decode!(choice["message"]["content"])
    usage = body["usage"]

    {:ok,
     %{
       steps: parse_steps(parsed),
       prompt_tokens: usage["prompt_tokens"],
       completion_tokens: usage["completion_tokens"],
       total_tokens: usage["total_tokens"]
     }}
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
