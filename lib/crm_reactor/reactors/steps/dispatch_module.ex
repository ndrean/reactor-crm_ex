defmodule CrmReactor.Reactors.Steps.DispatchModule do
  @moduledoc "Reactor step: route classified steps to the appropriate modules and combine results."
  use Reactor.Step

  alias CrmReactor.CRM.ExecutionLog
  alias CrmReactor.Reactors.Modules
  alias CrmReactor.Reactors.WorkflowInterpreter
  alias CrmReactor.Repo
  alias CrmReactor.Workers.PendingTimeoutWorker

  @module_map %{
    "contacts" => Modules.Contacts,
    "todos" => Modules.Todos,
    "data" => Modules.DataExport,
    "help" => Modules.Help
  }

  @destructive_actions ~w[update delete]
  @pending_timeout_seconds 15 * 60

  @impl true
  def run(
        %{
          classification: %{steps: steps},
          tenant: tenant,
          channel: channel,
          user_id: user_id,
          log: log,
          text: raw_text
        },
        _context,
        _options
      ) do
    destructive_count = Enum.count(steps, &(&1.action in @destructive_actions))

    if length(steps) > 1 and destructive_count > 1 do
      {:ok,
       %{
         output:
           "Je ne peux pas gérer plusieurs modifications ou suppressions à la fois. " <>
             "Envoyez ces demandes séparément.",
         action: "clarify"
       }}
    else
      context = %{
        tenant_schema: tenant.schema_name,
        company_name: tenant.company_name,
        admin_email: tenant[:admin_email],
        channel: channel,
        user_id: user_id,
        log_id: log.id,
        raw_text: raw_text
      }

      case WorkflowInterpreter.run(steps, @module_map, context) do
        {:ok, %{action: "clarify", confirm_items: items, confirm_step: step_template} = result} ->
          store_fanout_pending(items, step_template, result.output, log.id, context)

        other ->
          other
      end
    end
  end

  defp store_fanout_pending(items, step_template, output, log_id, context) do
    log =
      Repo.get!(ExecutionLog, log_id, prefix: context.tenant_schema)
      |> ExecutionLog.pending_changeset(%{
        action: step_template["action"],
        module: step_template["workflow"],
        proposed_params:
          Map.merge(step_template, %{
            "type" => "fanout",
            "items" => items
          })
      })
      |> Repo.update!(prefix: context.tenant_schema)

    schedule_pending_timeout(log.pending_id)

    {:ok,
     %{
       output: output,
       action: "pending",
       pending_type: "fanout",
       pending_id: log.pending_id
     }}
  end

  defp schedule_pending_timeout(pending_id) do
    %{"pending_id" => pending_id}
    |> PendingTimeoutWorker.new(schedule_in: @pending_timeout_seconds)
    |> Oban.insert()
  end
end
