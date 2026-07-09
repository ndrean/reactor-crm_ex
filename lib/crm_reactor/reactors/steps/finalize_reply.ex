defmodule CrmReactor.Reactors.Steps.FinalizeReply do
  @moduledoc "Reactor step: update execution log with result and token usage."
  use Reactor.Step

  alias CrmReactor.AI.ConversationCache
  alias CrmReactor.CRM.{ExecutionAttachment, ExecutionLog}
  alias CrmReactor.Repo
  alias CrmReactor.Workers.WebhookWorker

  require Logger

  @non_terminal_actions ~w(pending clarify unauthorized)

  @impl true
  def run(
        %{
          result: result,
          log: log,
          tenant: tenant,
          classification: classification,
          attachment: attachment,
          user_id: user_id,
          text: text
        },
        _context,
        _options
      ) do
    action = result[:action]

    if action != "pending" do
      first_step = List.first(classification.steps)

      log
      |> ExecutionLog.complete_changeset(%{
        action: action || first_step.action,
        module: first_step.workflow,
        routing_path: first_step[:routing_path] || "deterministic",
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

    if action not in @non_terminal_actions do
      enqueue_webhook(tenant, classification, result)
      ConversationCache.put(user_id, text, result.output)
    end

    {:ok, result}
  end

  defp enqueue_webhook(tenant, classification, result) do
    if tenant[:webhook_url] do
      first_step = List.first(classification.steps)

      args = %{
        "webhook_url" => tenant.webhook_url,
        "webhook_secret" => tenant.webhook_secret,
        "payload" => %{
          "tenant_id" => tenant.tenant_id,
          "workflow" => first_step.workflow,
          "action" => result[:action] || first_step.action,
          "output" => result.output,
          "data" => result[:data],
          "timestamp" => DateTime.utc_now() |> DateTime.to_iso8601()
        }
      }

      try do
        args |> WebhookWorker.new() |> Oban.insert()
      rescue
        e -> Logger.debug("Webhook not enqueued: #{inspect(e)}")
      catch
        :exit, _ -> :ok
      end
    end
  end
end
