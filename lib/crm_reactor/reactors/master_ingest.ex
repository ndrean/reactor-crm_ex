defmodule CrmReactor.Reactors.MasterIngest do
  @moduledoc "Main pipeline: tenant resolution, transcription, classification, dispatch."
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

  # :tenant (DB lookup) and :text (optional Whisper HTTP call) have no inter-dependency
  # and are run concurrently by Reactor before either feeds into :classification.
  step :tenant, CrmReactor.Reactors.Steps.ResolveTenant do
    argument(:user_id, input(:user_id))
  end

  step :text, CrmReactor.Reactors.Steps.Transcribe do
    argument(:raw_input, input(:raw_input))
    argument(:is_audio, input(:is_audio))
  end

  step :log, CrmReactor.Reactors.Steps.LogExecution do
    argument(:tenant, result(:tenant))
    argument(:raw_input, input(:raw_input))
    argument(:channel, input(:channel))
    argument(:user_id, input(:user_id))
    argument(:job_id, input(:job_id))
  end

  step :classification, CrmReactor.Reactors.Steps.ClassifyIntent do
    argument(:text, result(:text))
    argument(:attachment, input(:attachment))
    argument(:tenant, result(:tenant))
    argument(:user_id, input(:user_id))
  end

  step :result, CrmReactor.Reactors.Steps.DispatchModule do
    argument(:classification, result(:classification))
    argument(:tenant, result(:tenant))
    argument(:channel, input(:channel))
    argument(:user_id, input(:user_id))
    argument(:log, result(:log))
    argument(:text, result(:text))
  end

  step :finalize, CrmReactor.Reactors.Steps.FinalizeReply do
    argument(:result, result(:result))
    argument(:log, result(:log))
    argument(:tenant, result(:tenant))
    argument(:classification, result(:classification))
    argument(:attachment, input(:attachment))
    argument(:user_id, input(:user_id))
    argument(:text, result(:text))
  end

  return(:finalize)
end
