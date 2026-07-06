defmodule CrmReactor.Reactors.Steps.Transcribe do
  @moduledoc "Reactor step: transcribe voice input via Whisper, pass text through."
  use Reactor.Step

  alias CrmReactor.AI.Whisper

  @impl true
  def run(%{raw_input: raw_input, is_audio: true}, _context, _options) do
    Whisper.transcribe(raw_input)
  end

  def run(%{raw_input: raw_input, is_audio: _}, _context, _options) do
    {:ok, raw_input}
  end
end
