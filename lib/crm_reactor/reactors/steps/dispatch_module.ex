defmodule CrmReactor.Reactors.Steps.DispatchModule do
  @moduledoc "Reactor step: route classified steps to the appropriate modules and combine results."
  use Reactor.Step

  alias CrmReactor.AI.SubscriptionCache
  alias CrmReactor.CRM.ExecutionLog
  alias CrmReactor.Reactors.WorkflowInterpreter
  alias CrmReactor.Repo
  alias CrmReactor.Workers.PendingTimeoutWorker

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
    tenant_id = Map.get(tenant, :tenant_id)

    disabled =
      steps
      |> Enum.map(& &1.workflow)
      |> Enum.uniq()
      |> Enum.reject(&SubscriptionCache.enabled?(tenant_id, &1))

    destructive_count = Enum.count(steps, &(&1.action in @destructive_actions))

    cond do
      disabled != [] ->
        names = Enum.join(disabled, ", ")

        {:ok,
         %{
           output: "Cette fonctionnalité (#{names}) n'est pas disponible sur votre abonnement.",
           action: "unauthorized"
         }}

      length(steps) > 1 and destructive_count > 1 ->
        {:ok,
         %{
           output:
             "Je ne peux pas gérer plusieurs modifications ou suppressions à la fois. " <>
               "Envoyez ces demandes séparément.",
           action: "clarify"
         }}

      true ->
        context = %{
          tenant_schema: tenant.schema_name,
          company_name: tenant.company_name,
          admin_email: tenant[:admin_email],
          channel: channel,
          user_id: user_id,
          log_id: log.id,
          raw_text: raw_text
        }

        case WorkflowInterpreter.run(steps, workflow_modules(), context) do
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

    schedule_pending_timeout(log.pending_id, context.tenant_schema)

    {:ok,
     %{
       output: output,
       action: "pending",
       pending_type: "fanout",
       pending_id: log.pending_id
     }}
  end

  defp schedule_pending_timeout(pending_id, schema) do
    %{"pending_id" => pending_id, "schema_name" => schema}
    |> PendingTimeoutWorker.new(schedule_in: @pending_timeout_seconds)
    |> Oban.insert()
  end

  defp workflow_modules do
    Application.get_env(:crm_reactor, :workflow_modules)
  end
end
