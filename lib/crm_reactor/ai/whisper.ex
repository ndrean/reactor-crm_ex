defmodule CrmReactor.AI.Whisper do
  @moduledoc "Voice transcription via Whisper ASR or Mistral Voxtral API."

  alias CrmReactor.AI.Telemetry

  def transcribe(audio_url) do
    provider = Application.get_env(:crm_reactor, :whisper_provider, :local)

    with {:ok, %{status: 200, body: audio_data}} <-
           Req.get(audio_url, receive_timeout: 15_000, finch: CrmReactor.Finch) do
      case provider do
        :mistral -> transcribe_mistral(audio_data)
        _ -> transcribe_local(audio_data)
      end
    end
  end

  defp transcribe_mistral(audio_data) do
    api_key = Application.fetch_env!(:crm_reactor, :mistral_api_key)
    start_time = System.monotonic_time()

    case Req.post("https://api.mistral.ai/v1/audio/transcriptions",
           form_multipart: [
             file: {audio_data, filename: "audio.ogg", content_type: "audio/ogg"},
             model: "voxtral-mini-latest",
             language: "fr"
           ],
           headers: [{"authorization", "Bearer #{api_key}"}],
           receive_timeout: 30_000,
           finch: CrmReactor.Finch
         ) do
      {:ok, %{status: 200, body: body}} ->
        Telemetry.transcribe_stop(start_time, %{model: "voxtral-mini-latest", provider: :mistral})
        {:ok, body["text"]}

      {:ok, %{status: status, body: body}} ->
        {:error, "Voxtral error #{status}: #{inspect(body)}"}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp transcribe_local(audio_data) do
    whisper_url = Application.get_env(:crm_reactor, :whisper_url, "http://127.0.0.1:8000")
    start_time = System.monotonic_time()

    case Req.post("#{whisper_url}/v1/audio/transcriptions",
           form_multipart: [
             file: {audio_data, filename: "audio.ogg", content_type: "audio/ogg"},
             model: "small",
             language: "fr"
           ],
           receive_timeout: 30_000,
           finch: CrmReactor.Finch
         ) do
      {:ok, %{status: 200, body: body}} ->
        Telemetry.transcribe_stop(start_time, %{model: "whisper-small", provider: :local})
        {:ok, body["text"]}

      {:ok, %{status: status}} ->
        {:error, "Whisper error: #{status}"}

      {:error, reason} ->
        {:error, reason}
    end
  end
end
