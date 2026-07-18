defmodule CrmReactor.Reactors.Modules.Todos do
  @moduledoc "Task and appointment CRUD with deterministic and NL2SQL list paths."

  alias CrmReactor.AI.{QueryBuilder, Telemetry}
  alias CrmReactor.CRM.{Contact, ExecutionLog, Todo}
  alias CrmReactor.Reactors.PendingHelper
  alias CrmReactor.Repo
  alias CrmReactor.Workers.AppointmentReminderWorker
  import Ecto.Query

  require Logger

  # ── Todo: list (NL2SQL) ──────────────────────────────────────────────

  def execute(%{action: "list", routing_path: "nl2sql"} = ctx) do
    contact_name = ctx.params["contact_name"]

    case resolve_contact(contact_name, ctx.tenant_schema) do
      {:ambiguous, names} ->
        {:ok, disambiguation_result(contact_name, names)}

      contact ->
        case QueryBuilder.build_query(Todo, ctx.raw_text) do
          {:ok, nl2sql_query} ->
            query =
              from(t in nl2sql_query, where: t.created_by == ^ctx.user_id)
              |> apply_contact_filter(contact_name, contact)

            todos = Repo.all(with_contact_names(query), prefix: ctx.tenant_schema)

            {:ok,
             %{
               output: format_result(todos),
               action: "list",
               data: todos_data(todos)
             }}

          {:error, reason} ->
            Logger.warning("NL2SQL failed for todos list: #{inspect(reason)}, falling back")
            Telemetry.nl2sql_fallback_to_deterministic(%{module: "todos"})

            execute_deterministic_list(
              ctx.params,
              contact_name,
              ctx.tenant_schema,
              ctx.user_id,
              contact
            )
        end
    end
  end

  # ── Todo: list (deterministic) ───────────────────────────────────────

  def execute(%{action: "list"} = ctx) do
    contact_name = ctx.params["contact_name"]

    case resolve_contact(contact_name, ctx.tenant_schema) do
      {:ambiguous, names} ->
        {:ok, disambiguation_result(contact_name, names)}

      contact ->
        execute_deterministic_list(
          ctx.params,
          contact_name,
          ctx.tenant_schema,
          ctx.user_id,
          contact
        )
    end
  end

  # ── Todo: create ─────────────────────────────────────────────────────

  def execute(%{action: "create"} = ctx) do
    contact_id = resolve_contact_id(ctx.params["contact_name"], ctx.tenant_schema)

    case %Todo{}
         |> Todo.changeset(%{
           subject: extract_subject(ctx.params),
           due_date: parse_date(ctx.params["due_date"]),
           created_by: ctx.user_id,
           contact_id: contact_id
         })
         |> Repo.insert(prefix: ctx.tenant_schema) do
      {:ok, todo} ->
        due = if todo.due_date, do: " (échéance #{todo.due_date})", else: ""

        {:ok,
         %{
           output: "Tâche créée : #{todo.subject}#{due}",
           action: "create",
           data: %{
             "todo_id" => todo.id,
             "subject" => todo.subject,
             "contact_id" => todo.contact_id
           }
         }}

      {:error, changeset} ->
        msgs = Ecto.Changeset.traverse_errors(changeset, fn {m, _} -> m end) |> inspect()
        {:ok, %{output: "Impossible de créer la tâche : #{msgs}", action: "create"}}
    end
  end

  # ── Todo: complete ───────────────────────────────────────────────────

  def execute(%{action: "complete"} = ctx) do
    case find_todos(ctx) do
      [todo] ->
        case todo
             |> Ecto.Changeset.change(done: true)
             |> Repo.update(prefix: ctx.tenant_schema) do
          {:ok, _} ->
            {:ok, %{output: "Tâche complétée : #{todo.subject}", action: "complete"}}

          {:error, _changeset} ->
            {:ok, %{output: "Erreur lors de la complétion de la tâche.", action: "complete"}}
        end

      [] ->
        {:ok,
         %{
           output: "Aucune tâche trouvée pour \"#{extract_subject(ctx.params)}\".",
           action: "complete"
         }}

      _many ->
        {:ok, %{output: "Plusieurs tâches correspondent. Précisez.", action: "complete"}}
    end
  end

  # ── Todo: update / delete ────────────────────────────────────────────

  def execute(%{action: action} = ctx) when action in ["update", "delete"] do
    case find_todos(ctx) do
      [match] ->
        log =
          Repo.get!(ExecutionLog, ctx.log_id, prefix: ctx.tenant_schema)
          |> ExecutionLog.pending_changeset(%{
            action: action,
            module: "todos",
            proposed_params: Map.merge(ctx.params, %{"todo_id" => match.id})
          })
          |> Repo.update!(prefix: ctx.tenant_schema)

        schedule_pending_timeout(log.pending_id, ctx.tenant_schema)
        verb = if action == "delete", do: "la suppression", else: "la modification"

        {:ok,
         %{
           output: "Confirmez-vous #{verb} de \"#{match.subject}\" ?",
           action: "pending",
           pending_type: "confirm",
           pending_id: log.pending_id
         }}

      [] ->
        {:ok, %{output: "Aucune tâche trouvée.", action: action}}

      _many ->
        {:ok, %{output: "Plusieurs tâches correspondent. Précisez.", action: action}}
    end
  end

  # ── Appointment: create ──────────────────────────────────────────────

  def execute(%{action: "create_appointment"} = ctx) do
    contact_id = resolve_contact_id(ctx.params["contact_name"], ctx.tenant_schema)

    case parse_datetime(ctx.params["date"], ctx.params["time"]) do
      {:error, reason} ->
        {:ok, %{output: "Erreur de date/heure : #{reason}", action: "create_appointment"}}

      {:ok, starts_at} ->
        do_create_appointment(ctx, contact_id, starts_at)
    end
  end

  # ── Appointment: list ────────────────────────────────────────────────

  def execute(%{action: "list_appointments"} = ctx) do
    contact_name = ctx.params["contact_name"]

    base =
      from(t in Todo,
        where: not is_nil(t.starts_at) and t.done == false and t.created_by == ^ctx.user_id,
        order_by: [asc: t.starts_at]
      )

    base = apply_appointment_date_filter(base, ctx.params)
    base = apply_contact_filter(base, contact_name, ctx.tenant_schema)

    appointments = Repo.all(with_contact_names(base), prefix: ctx.tenant_schema)

    {:ok,
     %{
       output: format_appointments(appointments),
       action: "list_appointments",
       data: %{
         "appointments" =>
           Enum.map(appointments, fn a ->
             %{
               "id" => a.id,
               "subject" => a.subject,
               "starts_at" => a.starts_at && DateTime.to_iso8601(a.starts_at),
               "location" => a.location,
               "contact_id" => a.contact_id
             }
           end),
         "count" => length(appointments)
       }
     }}
  end

  # ── Appointment: cancel ──────────────────────────────────────────────

  def execute(%{action: "cancel_appointment"} = ctx) do
    case find_appointments(ctx) do
      [match] ->
        log =
          Repo.get!(ExecutionLog, ctx.log_id, prefix: ctx.tenant_schema)
          |> ExecutionLog.pending_changeset(%{
            action: "cancel_appointment",
            module: "todos",
            proposed_params: %{"todo_id" => match.id}
          })
          |> Repo.update!(prefix: ctx.tenant_schema)

        schedule_pending_timeout(log.pending_id, ctx.tenant_schema)
        date_str = Calendar.strftime(match.starts_at, "%d/%m/%Y à %Hh%M")

        {:ok,
         %{
           output: "Annuler le rendez-vous \"#{match.subject}\" du #{date_str} ?",
           action: "pending",
           pending_type: "confirm",
           pending_id: log.pending_id
         }}

      [] ->
        {:ok, %{output: "Aucun rendez-vous trouvé.", action: "cancel_appointment"}}

      _many ->
        {:ok,
         %{output: "Plusieurs rendez-vous correspondent. Précisez.", action: "cancel_appointment"}}
    end
  end

  # ── Appointment: reschedule ──────────────────────────────────────────

  def execute(%{action: "reschedule"} = ctx) do
    case find_appointments(ctx) do
      [match] ->
        log =
          Repo.get!(ExecutionLog, ctx.log_id, prefix: ctx.tenant_schema)
          |> ExecutionLog.pending_changeset(%{
            action: "reschedule",
            module: "todos",
            proposed_params:
              Map.merge(ctx.params, %{
                "todo_id" => match.id,
                "old_reminder_job_id" => match.reminder_job_id
              })
          })
          |> Repo.update!(prefix: ctx.tenant_schema)

        schedule_pending_timeout(log.pending_id, ctx.tenant_schema)
        date_str = Calendar.strftime(match.starts_at, "%d/%m/%Y à %Hh%M")

        {:ok,
         %{
           output: "Reprogrammer \"#{match.subject}\" (actuellement #{date_str}) ?",
           action: "pending",
           pending_type: "confirm",
           pending_id: log.pending_id
         }}

      [] ->
        {:ok, %{output: "Aucun rendez-vous trouvé.", action: "reschedule"}}

      _many ->
        {:ok, %{output: "Plusieurs rendez-vous correspondent. Précisez.", action: "reschedule"}}
    end
  end

  # ── Unsupported ──────────────────────────────────────────────────────

  def execute(%{action: action}) do
    {:ok, %{output: "Action todos non supportée : #{action}", action: action}}
  end

  # ══════════════════════════════════════════════════════════════════════
  # Private — shared
  # ══════════════════════════════════════════════════════════════════════

  defp find_todos(ctx) do
    subject = extract_subject(ctx.params)
    pattern = "%#{subject}%"

    query =
      from(t in Todo,
        where: ilike(t.subject, ^pattern) and t.done == false and t.created_by == ^ctx.user_id
      )
      |> apply_contact_filter(ctx.params["contact_name"], ctx.tenant_schema)

    matches = Repo.all(query, prefix: ctx.tenant_schema)

    case Enum.filter(matches, &(String.downcase(&1.subject) == String.downcase(subject))) do
      [_ | _] = exact -> exact
      [] -> matches
    end
  end

  defp find_appointments(ctx) do
    subject = extract_subject(ctx.params)
    pattern = "%#{subject}%"

    query =
      from(t in Todo,
        where:
          ilike(t.subject, ^pattern) and
            not is_nil(t.starts_at) and
            t.done == false and
            t.created_by == ^ctx.user_id
      )
      |> apply_contact_filter(ctx.params["contact_name"], ctx.tenant_schema)

    matches = Repo.all(query, prefix: ctx.tenant_schema)

    case Enum.filter(matches, &(String.downcase(&1.subject) == String.downcase(subject))) do
      [_ | _] = exact -> exact
      [] -> matches
    end
  end

  defp execute_deterministic_list(params, contact_name, schema, user_id, contact) do
    base = from(t in Todo, where: t.done == false and t.created_by == ^user_id)
    base = apply_contact_filter(base, contact_name, contact)
    base = apply_date_filters(base, params)
    query = from(t in base, order_by: t.due_date) |> with_contact_names()
    todos = Repo.all(query, prefix: schema)
    {:ok, %{output: format_result(todos), action: "list", data: todos_data(todos)}}
  end

  # ── Todo date filters (on due_date) ─────────────────────────────────

  defp apply_date_filters(query, %{"due_on" => on_str}) do
    case parse_date(on_str) do
      nil -> apply_date_filters(query, %{})
      on -> from(t in query, where: t.due_date == ^on)
    end
  end

  defp apply_date_filters(query, %{"due_before" => before_str, "due_after" => after_str}) do
    before = parse_date(before_str)
    after_ = parse_date(after_str)
    from(t in query, where: t.due_date >= ^after_ and t.due_date <= ^before)
  end

  defp apply_date_filters(query, %{"due_before" => before_str}) do
    today = Date.utc_today()

    case parse_date(before_str) do
      nil ->
        apply_date_filters(query, %{})

      before ->
        if Date.compare(before, today) == :lt do
          from(t in query, where: t.due_date <= ^before)
        else
          from(t in query, where: t.due_date >= ^today and t.due_date <= ^before)
        end
    end
  end

  defp apply_date_filters(query, %{"due_after" => after_str}) do
    case parse_date(after_str) do
      nil -> apply_date_filters(query, %{})
      after_ -> from(t in query, where: t.due_date >= ^after_)
    end
  end

  defp apply_date_filters(query, _params) do
    today = Date.utc_today()
    from(t in query, where: is_nil(t.due_date) or t.due_date >= ^today)
  end

  # ── Appointment date filters (on starts_at) ─────────────────────────

  defp apply_appointment_date_filter(query, %{"due_on" => on_str}) do
    case parse_date(on_str) do
      nil -> apply_appointment_date_filter(query, %{})
      date -> appointment_date_range(query, date, date)
    end
  end

  defp apply_appointment_date_filter(query, %{
         "due_before" => before_str,
         "due_after" => after_str
       }) do
    case {parse_date(after_str), parse_date(before_str)} do
      {nil, _} -> apply_appointment_date_filter(query, %{"due_before" => before_str})
      {_, nil} -> apply_appointment_date_filter(query, %{"due_after" => after_str})
      {after_d, before_d} -> appointment_date_range(query, after_d, before_d)
    end
  end

  defp apply_appointment_date_filter(query, %{"due_before" => before_str}) do
    today = Date.utc_today()

    case parse_date(before_str) do
      nil ->
        apply_appointment_date_filter(query, %{})

      before ->
        if Date.compare(before, today) == :lt do
          end_dt = DateTime.new!(before, ~T[23:59:59], "Etc/UTC")
          from(t in query, where: t.starts_at <= ^end_dt)
        else
          appointment_date_range(query, today, before)
        end
    end
  end

  defp apply_appointment_date_filter(query, %{"due_after" => after_str}) do
    case parse_date(after_str) do
      nil ->
        apply_appointment_date_filter(query, %{})

      after_d ->
        start_dt = DateTime.new!(after_d, ~T[00:00:00], "Etc/UTC")
        from(t in query, where: t.starts_at >= ^start_dt)
    end
  end

  defp apply_appointment_date_filter(query, %{"date" => date_str}) when is_binary(date_str) do
    apply_appointment_date_filter(query, %{"due_on" => date_str})
  end

  defp apply_appointment_date_filter(query, %{"period" => "today"}) do
    today = Date.utc_today()
    appointment_date_range(query, today, today)
  end

  defp apply_appointment_date_filter(query, %{"period" => "week"}) do
    today = Date.utc_today()
    appointment_date_range(query, today, Date.add(today, 7))
  end

  defp apply_appointment_date_filter(query, _params) do
    now = DateTime.utc_now()
    from(t in query, where: t.starts_at >= ^now)
  end

  defp appointment_date_range(query, from_date, to_date) do
    start_dt = DateTime.new!(from_date, ~T[00:00:00], "Etc/UTC")
    end_dt = DateTime.new!(to_date, ~T[23:59:59], "Etc/UTC")
    from(t in query, where: t.starts_at >= ^start_dt and t.starts_at <= ^end_dt)
  end

  # ── Contact resolution ──────────────────────────────────────────────

  defp apply_contact_filter(query, nil, _), do: query
  defp apply_contact_filter(query, _name, :all), do: query

  defp apply_contact_filter(query, name, :not_found) do
    pattern = "%#{name}%"
    from(t in query, where: ilike(t.subject, ^pattern))
  end

  defp apply_contact_filter(query, name, {:found, contact_id}) do
    pattern = "%#{name}%"
    from(t in query, where: t.contact_id == ^contact_id or ilike(t.subject, ^pattern))
  end

  defp apply_contact_filter(query, name, schema) when is_binary(schema) do
    pattern = "%#{name}%"

    case resolve_contact_id(name, schema) do
      nil -> from(t in query, where: ilike(t.subject, ^pattern))
      id -> from(t in query, where: t.contact_id == ^id or ilike(t.subject, ^pattern))
    end
  end

  defp resolve_contact(nil, _schema), do: :all

  defp resolve_contact(name, schema) do
    words = String.split(name, ~r/\s+/, trim: true)

    query =
      Enum.reduce(words, from(c in Contact), fn word, q ->
        pattern = "%#{word}%"
        from c in q, where: ilike(c.first_name, ^pattern) or ilike(c.last_name, ^pattern)
      end)

    case Repo.all(query, prefix: schema) do
      [contact] -> {:found, contact.id}
      [] -> :not_found
      contacts -> {:ambiguous, Enum.map(contacts, &display_name/1)}
    end
  end

  defp resolve_contact_id(nil, _schema), do: nil

  defp resolve_contact_id(name, schema) do
    case resolve_contact(name, schema) do
      {:found, id} -> id
      _ -> nil
    end
  end

  # ── Formatting ──────────────────────────────────────────────────────

  defp disambiguation_result(name, names) do
    %{
      output:
        "Plusieurs contacts correspondent à « #{name} » : #{Enum.join(names, ", ")}. " <>
          "Précisez le nom complet.",
      action: "list",
      data: %{"todos" => [], "count" => 0}
    }
  end

  defp format_result([]), do: "Aucune tâche en cours."

  defp format_result(todos) do
    "Tâches en cours :\n" <>
      Enum.map_join(todos, "\n", fn t ->
        due = if t.due_date, do: " (#{t.due_date})", else: ""
        contact = format_contact_suffix(t.contact_name)
        "• #{t.subject}#{contact}#{due}"
      end)
  end

  defp format_appointments([]), do: "Aucun rendez-vous à venir."

  defp format_appointments(appointments) do
    "Rendez-vous à venir :\n" <>
      Enum.map_join(appointments, "\n", fn a ->
        date_str = Calendar.strftime(a.starts_at, "%d/%m/%Y à %Hh%M")
        location = if a.location, do: " (#{a.location})", else: ""
        contact = format_contact_suffix(a.contact_name)
        "• #{a.subject} — #{date_str}#{location}#{contact}"
      end)
  end

  defp format_contact_suffix(nil), do: ""
  defp format_contact_suffix(name), do: " [#{name}]"

  defp with_contact_names(query) do
    from(t in query,
      left_join: c in Contact,
      on: c.id == t.contact_id,
      select_merge: %{
        contact_name:
          fragment(
            "NULLIF(concat_ws(' ', ?, ?), '')",
            c.first_name,
            c.last_name
          )
      }
    )
  end

  defp todos_data(todos) do
    %{
      "todos" =>
        Enum.map(todos, fn t ->
          %{
            "id" => t.id,
            "subject" => t.subject,
            "due_date" => t.due_date && to_string(t.due_date),
            "contact_id" => t.contact_id,
            "done" => t.done
          }
        end),
      "count" => length(todos)
    }
  end

  # ── Appointment creation helpers ────────────────────────────────────

  defp do_create_appointment(ctx, contact_id, starts_at) do
    ends_at = compute_ends_at(starts_at, ctx.params["duration"])
    reminder_minutes = parse_reminder_minutes(ctx.params["reminder_minutes"])

    attrs = %{
      subject: extract_subject(ctx.params),
      starts_at: starts_at,
      ends_at: ends_at,
      location: ctx.params["location"],
      reminder_minutes: reminder_minutes,
      created_by: ctx.user_id,
      contact_id: contact_id
    }

    case %Todo{} |> Todo.changeset(attrs) |> Repo.insert(prefix: ctx.tenant_schema) do
      {:ok, todo} ->
        job_id = schedule_reminder(todo, ctx)

        if job_id do
          todo
          |> Ecto.Changeset.change(reminder_job_id: job_id)
          |> Repo.update!(prefix: ctx.tenant_schema)
        end

        location_str = if todo.location, do: " à #{todo.location}", else: ""
        date_str = Calendar.strftime(starts_at, "%d/%m/%Y à %Hh%M")

        {:ok,
         %{
           output: "Rendez-vous créé : #{todo.subject} le #{date_str}#{location_str}",
           action: "create_appointment",
           data: %{
             "todo_id" => todo.id,
             "subject" => todo.subject,
             "starts_at" => DateTime.to_iso8601(starts_at),
             "reminder_job_id" => job_id
           }
         }}

      {:error, changeset} ->
        msgs = Ecto.Changeset.traverse_errors(changeset, fn {m, _} -> m end) |> inspect()

        {:ok,
         %{output: "Impossible de créer le rendez-vous : #{msgs}", action: "create_appointment"}}
    end
  end

  defp parse_datetime(date_str, time_str) when is_binary(date_str) and is_binary(time_str) do
    time_str = if String.length(time_str) == 5, do: time_str <> ":00", else: time_str

    with {:ok, date} <- Date.from_iso8601(date_str),
         {:ok, time} <- Time.from_iso8601(time_str) do
      {:ok, DateTime.new!(date, time, "Etc/UTC")}
    else
      _ -> {:error, "format invalide (attendu date: YYYY-MM-DD, heure: HH:MM)"}
    end
  end

  defp parse_datetime(_, _), do: {:error, "date et heure sont obligatoires"}

  defp compute_ends_at(starts_at, nil), do: DateTime.add(starts_at, 3600, :second)

  defp compute_ends_at(starts_at, duration) when is_binary(duration) do
    case Integer.parse(duration) do
      {minutes, _} -> DateTime.add(starts_at, minutes * 60, :second)
      :error -> DateTime.add(starts_at, 3600, :second)
    end
  end

  defp compute_ends_at(starts_at, duration) when is_integer(duration) do
    DateTime.add(starts_at, duration * 60, :second)
  end

  defp parse_reminder_minutes(nil), do: 30

  defp parse_reminder_minutes(val) when is_binary(val) do
    case Integer.parse(val) do
      {n, _} -> n
      :error -> 30
    end
  end

  defp parse_reminder_minutes(val) when is_integer(val), do: val

  defp schedule_reminder(todo, ctx) do
    reminder_minutes = todo.reminder_minutes || 30
    scheduled_at = DateTime.add(todo.starts_at, -reminder_minutes * 60, :second)

    if DateTime.compare(scheduled_at, DateTime.utc_now()) == :gt do
      {:ok, job} =
        %{
          "todo_id" => todo.id,
          "tenant_schema" => ctx.tenant_schema,
          "channel" => to_string(ctx[:channel] || "http"),
          "user_id" => ctx.user_id,
          "subject" => todo.subject
        }
        |> AppointmentReminderWorker.new(scheduled_at: scheduled_at)
        |> Oban.insert()

      job.id
    else
      nil
    end
  end

  # ── Common helpers ──────────────────────────────────────────────────

  defp display_name(c),
    do: [c.first_name, c.last_name] |> Enum.filter(& &1) |> Enum.join(" ")

  defp extract_subject(params) do
    params["subject"] || params["title"] || params["description"] || params["name"] || ""
  end

  defp parse_date(nil), do: nil

  defp parse_date(date_str) when is_binary(date_str) do
    case Date.from_iso8601(date_str) do
      {:ok, date} -> date
      _ -> nil
    end
  end

  defp schedule_pending_timeout(pending_id, schema),
    do: PendingHelper.schedule_pending_timeout(pending_id, schema)
end
