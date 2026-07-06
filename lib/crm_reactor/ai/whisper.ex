defmodule CrmReactor.AI.Whisper do
  @moduledoc "Voice transcription via Whisper ASR API."
  def transcribe(audio_url) do
    whisper_url = Application.get_env(:crm_reactor, :whisper_url, "http://localhost:8000")

    with {:ok, %{body: audio_data}} <- Req.get(audio_url, receive_timeout: 15_000),
         {:ok, %{status: 200, body: body}} <-
           Req.post("#{whisper_url}/v1/audio/transcriptions",
             form_multipart: [
               file: {"audio.ogg", audio_data},
               model: "small",
               language: "fr"
             ],
             receive_timeout: 30_000
           ) do
      {:ok, body["text"]}
    else
      {:ok, %{status: status}} -> {:error, "Whisper error: #{status}"}
      {:error, reason} -> {:error, reason}
    end
  end
end
