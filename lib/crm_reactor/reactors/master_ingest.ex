defmodule CrmReactor.Reactors.MasterIngest do
  @moduledoc "Main pipeline: transcription, classification, dispatch. Tenant is resolved at the transport boundary."
  use Reactor

  middlewares do
    middleware(Reactor.Middleware.Telemetry)
  end

  input(:user_id)
  input(:raw_input)
  input(:is_audio)
  input(:channel)
  input(:job_id)
  input(:attachment)
  input(:tenant)

  step :text, CrmReactor.Reactors.Steps.Transcribe do
    argument(:raw_input, input(:raw_input))
    argument(:is_audio, input(:is_audio))
  end

  step :log, CrmReactor.Reactors.Steps.LogExecution do
    argument(:tenant, input(:tenant))
    argument(:raw_input, input(:raw_input))
    argument(:channel, input(:channel))
    argument(:user_id, input(:user_id))
    argument(:job_id, input(:job_id))
  end

  step :classification, CrmReactor.Reactors.Steps.ClassifyIntent do
    argument(:text, result(:text))
    argument(:attachment, input(:attachment))
    argument(:tenant, input(:tenant))
    argument(:user_id, input(:user_id))
  end

  step :result, CrmReactor.Reactors.Steps.DispatchModule do
    argument(:classification, result(:classification))
    argument(:tenant, input(:tenant))
    argument(:channel, input(:channel))
    argument(:user_id, input(:user_id))
    argument(:log, result(:log))
    argument(:text, result(:text))
  end

  step :finalize, CrmReactor.Reactors.Steps.FinalizeReply do
    argument(:result, result(:result))
    argument(:log, result(:log))
    argument(:tenant, input(:tenant))
    argument(:classification, result(:classification))
    argument(:attachment, input(:attachment))
    argument(:user_id, input(:user_id))
    argument(:text, result(:text))
  end

  return(:finalize)
end
