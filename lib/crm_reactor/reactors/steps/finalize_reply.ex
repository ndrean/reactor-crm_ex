defmodule CrmReactor.Reactors.Steps.FinalizeReply do
  @moduledoc "Reactor step: update execution log with result and token usage."
  use Reactor.Step

  alias CrmReactor.CRM.{ExecutionAttachment, ExecutionLog}
  alias CrmReactor.Repo

  @impl true
  def run(
        %{
          result: result,
          log: log,
          tenant: tenant,
          classification: classification,
          attachment: attachment
        },
        _context,
        _options
      ) do
    if result[:action] != "pending" do
      first_step = List.first(classification.steps)

      log
      |> ExecutionLog.complete_changeset(%{
        action: result[:action] || first_step.action,
        module: first_step.workflow,
        routing_path: "deterministic",
        output: result.output,
        prompt_tokens: classification[:prompt_tokens],
        completion_tokens: classification[:completion_tokens],
        total_tokens: classification[:total_tokens]
      })
      |> Repo.update(prefix: tenant.schema_name)
    end

    if attachment do
      %ExecutionAttachment{}
      |> ExecutionAttachment.changeset(%{
        execution_log_id: log.id,
        filename: attachment.filename,
        content_type: attachment.content_type,
        size_bytes: attachment.size_bytes,
        storage_key: attachment.storage_key
      })
      |> Repo.insert(prefix: tenant.schema_name)
    end

    {:ok, result}
  end
end
