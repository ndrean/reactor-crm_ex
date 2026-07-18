defmodule CrmReactor.Reactors.Modules.Mutations do
  @moduledoc "2-step confirm/reject flow for contact and todo mutations."

  alias CrmReactor.CRM.{Contact, ExecutionLog, Expense, Todo}
  alias CrmReactor.Reactors.Modules.DataExport
  alias CrmReactor.Repo
  alias CrmReactor.Tenants.{Tenant, UserMapping}
  alias CrmReactor.Workers.AppointmentReminderWorker
  import Ecto.Query

  require Logger

  @doc """
  Confirms or rejects a pending mutation.

  The search is scoped to the user's tenant schema and the caller must match
  the `triggered_by` on the log entry.
  """
  def confirm(pending_id, decision, user_id) when is_binary(user_id) do
    with schema when is_binary(schema) <- resolve_schema(user_id),
         log when not is_nil(log) <- find_pending_in_schema(pending_id, schema),
         :ok <- authorize(log.triggered_by, user_id) do
      dispatch_confirm(log, schema, decision)
    else
      nil -> {:error, :pending_not_found}
      {:error, :unauthorized} = err -> err
    end
  end

  @doc "System-only confirm scoped to a known schema (avoids scanning all tenants)."
  def confirm_system(pending_id, decision, schema) when is_binary(schema) do
    case find_pending_in_schema(pending_id, schema) do
      nil -> {:error, :pending_not_found}
      log -> dispatch_confirm(log, schema, decision)
    end
  end

  defp authorize(triggered_by, user_id) when triggered_by == user_id, do: :ok
  defp authorize(_triggered_by, _user_id), do: {:error, :unauthorized}

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

  defp resolve_schema(user_id) do
    Repo.one(
      from m in UserMapping,
        join: t in Tenant,
        on: t.tenant_id == m.tenant_id,
        where: m.email == ^user_id or m.telegram_id == ^user_id,
        select: t.schema_name
    )
  end

  defp find_pending_in_schema(pending_id, schema) do
    case pending_log_query(pending_id) |> Repo.one(prefix: schema) do
      nil -> nil
      log -> Map.put(log, :schema, schema)
    end
  end

  defp pending_log_query(pending_id) do
    from(l in ExecutionLog,
      where: l.pending_id == ^pending_id and l.status == "pending",
      select: %{
        id: l.id,
        action: l.action,
        module: l.module,
        proposed_params: l.proposed_params,
        triggered_by: l.triggered_by
      }
    )
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

        case Map.get(workflow_modules(), params["workflow"]) do
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
    Repo.transaction(fn ->
      contact = Repo.get!(Contact, params["contact_id"], prefix: schema)
      updates = Map.drop(params, ["contact_id", "search_name", "name"])
      contact |> Contact.changeset(updates) |> Repo.update!(prefix: schema)
      finalize_log!(log, schema, "Contact modifié avec succès.")
    end)
    |> unwrap_transaction(log)
  end

  defp execute_mutation(
         %{module: "contacts", action: "delete", proposed_params: params} = log,
         schema
       ) do
    Repo.transaction(fn ->
      Repo.get!(Contact, params["contact_id"], prefix: schema) |> Repo.delete!(prefix: schema)
      finalize_log!(log, schema, "Contact supprimé.")
    end)
    |> unwrap_transaction(log)
  end

  defp execute_mutation(
         %{module: "todos", action: "update", proposed_params: params} = log,
         schema
       ) do
    Repo.transaction(fn ->
      todo = Repo.get!(Todo, params["todo_id"], prefix: schema)
      updates = prepare_todo_updates(params)
      todo |> Todo.changeset(updates) |> Repo.update!(prefix: schema)
      finalize_log!(log, schema, "Tâche modifiée avec succès.")
    end)
    |> unwrap_transaction(log)
  end

  defp execute_mutation(
         %{module: "todos", action: "delete", proposed_params: params} = log,
         schema
       ) do
    Repo.transaction(fn ->
      Repo.get!(Todo, params["todo_id"], prefix: schema) |> Repo.delete!(prefix: schema)
      finalize_log!(log, schema, "Tâche supprimée.")
    end)
    |> unwrap_transaction(log)
  end

  defp execute_mutation(
         %{module: "expenses", action: "delete", proposed_params: params} = log,
         schema
       ) do
    Repo.transaction(fn ->
      Repo.get!(Expense, params["expense_id"], prefix: schema) |> Repo.delete!(prefix: schema)
      finalize_log!(log, schema, "Note de frais supprimée.")
    end)
    |> unwrap_transaction(log)
  end

  defp execute_mutation(
         %{module: "todos", action: "cancel_appointment", proposed_params: params} = log,
         schema
       ) do
    result =
      Repo.transaction(fn ->
        todo = Repo.get!(Todo, params["todo_id"], prefix: schema)
        todo |> Ecto.Changeset.change(done: true) |> Repo.update!(prefix: schema)
        output = "Rendez-vous annulé : #{todo.subject}"
        finalize_log!(log, schema, output)
        %{reminder_job_id: todo.reminder_job_id, output: output}
      end)

    case result do
      {:ok, %{reminder_job_id: job_id, output: output}} ->
        if job_id, do: Oban.cancel_job(job_id)
        {:ok, %{output: output, action: log.action}}

      error ->
        unwrap_transaction(error, log)
    end
  end

  defp execute_mutation(
         %{module: "todos", action: "reschedule", proposed_params: params} = log,
         schema
       ) do
    case parse_reschedule_datetime(params) do
      {:error, :invalid} ->
        complete_log(log, schema, "Erreur : date/heure invalide pour la reprogrammation.")

      {:ok, new_starts_at, new_ends_at} ->
        do_reschedule(log, schema, params, new_starts_at, new_ends_at)
    end
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

  # Used inside Repo.transaction — raises on failure to trigger rollback.
  defp finalize_log!(log, schema, output) do
    Repo.get!(ExecutionLog, log.id, prefix: schema)
    |> ExecutionLog.complete_changeset(%{output: output, action: log.action, module: log.module})
    |> Repo.update!(prefix: schema)

    %{output: output, action: log.action}
  end

  # Used outside transactions (reject, provide_export_email, fanout, unsupported action).
  defp complete_log(log, schema, output) do
    Repo.get!(ExecutionLog, log.id, prefix: schema)
    |> ExecutionLog.complete_changeset(%{output: output, action: log.action, module: log.module})
    |> Repo.update!(prefix: schema)

    {:ok, %{output: output, action: log.action}}
  end

  defp unwrap_transaction({:ok, result}, _log), do: {:ok, result}

  defp unwrap_transaction({:error, reason}, log) do
    Logger.warning("Mutation failed for log #{log.id}: #{inspect(reason)}")
    {:ok, %{output: "Erreur lors de l'opération. Veuillez réessayer.", action: log.action}}
  end

  defp prepare_todo_updates(params) do
    params
    |> Map.drop(["todo_id", "subject"])
    |> then(fn m ->
      case Map.pop(m, "new_subject") do
        {nil, m} -> m
        {val, m} -> Map.put(m, "subject", val)
      end
    end)
  end

  defp parse_reschedule_datetime(params) do
    new_date = params["new_date"] || params["date"]
    new_time = params["new_time"] || params["time"]

    time_str =
      if is_binary(new_time) && String.length(new_time) == 5,
        do: new_time <> ":00",
        else: new_time

    with {:ok, date} <- Date.from_iso8601(new_date || ""),
         {:ok, time} <- Time.from_iso8601(time_str || "") do
      starts_at = DateTime.new!(date, time, "Etc/UTC")
      {:ok, starts_at, DateTime.add(starts_at, 3600, :second)}
    else
      _ -> {:error, :invalid}
    end
  end

  defp do_reschedule(log, schema, params, new_starts_at, new_ends_at) do
    date_str = Calendar.strftime(new_starts_at, "%d/%m/%Y à %Hh%M")

    result =
      Repo.transaction(fn ->
        todo = Repo.get!(Todo, params["todo_id"], prefix: schema)

        todo
        |> Ecto.Changeset.change(
          starts_at: new_starts_at,
          ends_at: new_ends_at,
          reminder_job_id: nil
        )
        |> Repo.update!(prefix: schema)

        finalize_log!(log, schema, "Rendez-vous reprogrammé au #{date_str}")
        %{todo: todo, reminder_minutes: todo.reminder_minutes || 30}
      end)

    case result do
      {:ok, %{todo: todo, reminder_minutes: reminder_minutes}} ->
        if params["old_reminder_job_id"], do: Oban.cancel_job(params["old_reminder_job_id"])

        new_job_id = schedule_reschedule_reminder(todo, new_starts_at, reminder_minutes, schema)

        if new_job_id do
          Repo.get!(Todo, todo.id, prefix: schema)
          |> Ecto.Changeset.change(reminder_job_id: new_job_id)
          |> Repo.update!(prefix: schema)
        end

        {:ok, %{output: "Rendez-vous reprogrammé au #{date_str}", action: log.action}}

      error ->
        unwrap_transaction(error, log)
    end
  end

  defp schedule_reschedule_reminder(todo, new_starts_at, reminder_minutes, schema) do
    scheduled_at = DateTime.add(new_starts_at, -reminder_minutes * 60, :second)

    if DateTime.compare(scheduled_at, DateTime.utc_now()) == :gt do
      {:ok, job} =
        %{
          "todo_id" => todo.id,
          "tenant_schema" => schema,
          "channel" => "http",
          "user_id" => todo.created_by,
          "subject" => todo.subject
        }
        |> AppointmentReminderWorker.new(scheduled_at: scheduled_at)
        |> Oban.insert()

      job.id
    else
      nil
    end
  end

  defp workflow_modules do
    Application.get_env(:crm_reactor, :workflow_modules)
  end
end
