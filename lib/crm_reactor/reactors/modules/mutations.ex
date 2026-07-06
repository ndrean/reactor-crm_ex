defmodule CrmReactor.Reactors.Modules.Mutations do
  @moduledoc "2-step confirm/reject flow for contact and todo mutations."

  alias CrmReactor.CRM.{Contact, ExecutionLog, Todo}
  alias CrmReactor.Reactors.Modules
  alias CrmReactor.Reactors.Modules.DataExport
  alias CrmReactor.Repo
  alias CrmReactor.Tenants.Tenant
  import Ecto.Query

  @module_map %{
    "contacts" => Modules.Contacts,
    "todos" => Modules.Todos,
    "data" => Modules.DataExport,
    "help" => Modules.Help
  }

  def confirm(pending_id, decision) do
    with log when not is_nil(log) <- find_pending_log(pending_id),
         schema <- log.schema do
      dispatch_confirm(log, schema, decision)
    else
      nil -> {:error, :pending_not_found}
    end
  end

  # Fan-out confirmation: execute N queued operations.
  defp dispatch_confirm(%{proposed_params: %{"type" => "fanout"}} = log, schema, "confirm"),
    do: execute_fanout(log, schema)

  # Export-email collection: any decision is treated as the proposed email.
  defp dispatch_confirm(%{proposed_params: %{"type" => "export_email"}} = log, schema, email),
    do: provide_export_email(log, schema, email)

  defp dispatch_confirm(log, schema, "confirm"), do: execute_mutation(log, schema)
  defp dispatch_confirm(log, schema, "reject"), do: reject(log, schema)
  defp dispatch_confirm(_, _, _), do: {:error, :invalid_decision}

  defp provide_export_email(log, schema, email) do
    if valid_email?(email) do
      tenant = Repo.get_by!(Tenant, schema_name: schema)
      tenant |> Ecto.Changeset.change(admin_email: email) |> Repo.update!()

      case DataExport.execute(%{
             action: "dump",
             tenant_schema: schema,
             admin_email: email,
             company_name: tenant.company_name
           }) do
        {:ok, export_result} -> complete_log(log, schema, export_result.output)
        {:error, _} = error -> error
      end
    else
      {:error, :invalid_email}
    end
  end

  defp valid_email?(email),
    do: is_binary(email) and String.match?(email, ~r/^[^\s@]+@[^\s@]+\.[^\s@]+$/)

  defp find_pending_log(pending_id) do
    schemas =
      from(t in Tenant, select: t.schema_name)
      |> Repo.all()

    Enum.find_value(schemas, fn schema ->
      case from(l in ExecutionLog,
             where: l.pending_id == ^pending_id and l.status == "pending",
             select: %{
               id: l.id,
               action: l.action,
               module: l.module,
               proposed_params: l.proposed_params,
               triggered_by: l.triggered_by
             }
           )
           |> Repo.one(prefix: schema) do
        nil -> nil
        log -> Map.put(log, :schema, schema)
      end
    end)
  end

  defp execute_fanout(
         %{proposed_params: params, triggered_by: user_id} = log,
         schema
       ) do
    items = params["items"]
    map_param = params["map_param"]

    results =
      Enum.map(items, fn item ->
        step_params = Map.put(params["params"] || %{}, map_param, item)

        case Map.get(@module_map, params["workflow"]) do
          nil ->
            {:ok, %{output: "Module inconnu : #{params["workflow"]}", action: "none"}}

          module ->
            module.execute(%{
              action: params["action"],
              params: step_params,
              routing_path: params["routing_path"] || "deterministic",
              raw_text: "",
              tenant_schema: schema,
              company_name: "",
              admin_email: nil,
              channel: :http,
              user_id: user_id,
              log_id: log.id
            })
        end
      end)

    {oks, _errors} = Enum.split_with(results, &match?({:ok, _}, &1))
    n_ok = length(oks)

    output =
      if oks != [] do
        Enum.map_join(oks, "\n", fn {:ok, r} -> r.output end)
      else
        "Aucune opération effectuée."
      end

    complete_log(log, schema, "#{n_ok} opération(s) effectuée(s).\n#{output}")
  end

  defp execute_mutation(
         %{module: "contacts", action: "update", proposed_params: params} = log,
         schema
       ) do
    contact = Repo.get!(Contact, params["contact_id"], prefix: schema)

    updates = Map.drop(params, ["contact_id", "search_name", "name"])

    contact |> Contact.changeset(updates) |> Repo.update!(prefix: schema)
    complete_log(log, schema, "Contact modifié avec succès.")
  end

  defp execute_mutation(
         %{module: "contacts", action: "delete", proposed_params: params} = log,
         schema
       ) do
    Repo.get!(Contact, params["contact_id"], prefix: schema) |> Repo.delete!(prefix: schema)
    complete_log(log, schema, "Contact supprimé.")
  end

  defp execute_mutation(
         %{module: "todos", action: "update", proposed_params: params} = log,
         schema
       ) do
    todo = Repo.get!(Todo, params["todo_id"], prefix: schema)

    updates =
      params
      |> Map.drop(["todo_id", "subject"])
      |> then(fn m ->
        case Map.pop(m, "new_subject") do
          {nil, m} -> m
          {val, m} -> Map.put(m, "subject", val)
        end
      end)

    todo |> Todo.changeset(updates) |> Repo.update!(prefix: schema)
    complete_log(log, schema, "Tâche modifiée avec succès.")
  end

  defp execute_mutation(
         %{module: "todos", action: "delete", proposed_params: params} = log,
         schema
       ) do
    Repo.get!(Todo, params["todo_id"], prefix: schema) |> Repo.delete!(prefix: schema)
    complete_log(log, schema, "Tâche supprimée.")
  end

  defp execute_mutation(log, schema) do
    complete_log(log, schema, "Action non supportée.")
  end

  defp reject(log, schema) do
    Repo.get!(ExecutionLog, log.id, prefix: schema)
    |> ExecutionLog.error_changeset(%{error_message: "Rejected by user"})
    |> Ecto.Changeset.put_change(:status, "rejected")
    |> Repo.update!(prefix: schema)

    {:ok, %{output: "Action annulée.", action: "rejected"}}
  end

  defp complete_log(log, schema, output) do
    Repo.get!(ExecutionLog, log.id, prefix: schema)
    |> ExecutionLog.complete_changeset(%{output: output, action: log.action, module: log.module})
    |> Repo.update!(prefix: schema)

    {:ok, %{output: output, action: log.action}}
  end
end
