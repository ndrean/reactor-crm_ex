defmodule CrmReactor.Reactors.Modules.Appointments do
  @moduledoc "Appointments CRUD: create, list, cancel, reschedule with reminders."

  alias CrmReactor.CRM.{Contact, ExecutionLog, Todo}
  alias CrmReactor.Repo
  alias CrmReactor.Workers.{AppointmentReminderWorker, PendingTimeoutWorker}
  import Ecto.Query

  # ── Create ─────────────────────────────────────────────────────────────

  def execute(%{action: "create"} = ctx) do
    contact_id = resolve_contact_id(ctx.params["contact_name"], ctx.tenant_schema)

    case parse_datetime(ctx.params["date"], ctx.params["time"]) do
      {:error, reason} ->
        {:ok, %{output: "Erreur de date/heure : #{reason}", action: "create"}}

      {:ok, starts_at} ->
        do_create(ctx, contact_id, starts_at)
    end
  end

  # ── List ───────────────────────────────────────────────────────────────

  def execute(%{action: "list"} = ctx) do
    contact_name = ctx.params["contact_name"]

    base =
      from(t in Todo,
        where: not is_nil(t.starts_at) and t.done == false and t.created_by == ^ctx.user_id,
        order_by: [asc: t.starts_at]
      )

    base = apply_date_filter(base, ctx.params)
    base = apply_contact_filter(base, contact_name, ctx.tenant_schema)

    appointments = Repo.all(base, prefix: ctx.tenant_schema)

    {:ok,
     %{
       output: format_appointments(appointments, ctx.tenant_schema),
       action: "list",
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

  # ── Cancel ─────────────────────────────────────────────────────────────

  def execute(%{action: "cancel"} = ctx) do
    case find_appointments(ctx) do
      [match] ->
        log =
          Repo.get!(ExecutionLog, ctx.log_id, prefix: ctx.tenant_schema)
          |> ExecutionLog.pending_changeset(%{
            action: "cancel",
            module: "appointments",
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
        {:ok, %{output: "Aucun rendez-vous trouvé.", action: "cancel"}}

      _many ->
        {:ok, %{output: "Plusieurs rendez-vous correspondent. Précisez.", action: "cancel"}}
    end
  end

  # ── Reschedule ─────────────────────────────────────────────────────────

  def execute(%{action: "reschedule"} = ctx) do
    case find_appointments(ctx) do
      [match] ->
        log =
          Repo.get!(ExecutionLog, ctx.log_id, prefix: ctx.tenant_schema)
          |> ExecutionLog.pending_changeset(%{
            action: "reschedule",
            module: "appointments",
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

  # ── Unsupported ────────────────────────────────────────────────────────

  def execute(%{action: action}) do
    {:ok, %{output: "Action appointments non supportée : #{action}", action: action}}
  end

  # ── Private ────────────────────────────────────────────────────────────

  defp do_create(ctx, contact_id, starts_at) do
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
           action: "create",
           data: %{
             "todo_id" => todo.id,
             "subject" => todo.subject,
             "starts_at" => DateTime.to_iso8601(starts_at),
             "reminder_job_id" => job_id
           }
         }}

      {:error, changeset} ->
        msgs = Ecto.Changeset.traverse_errors(changeset, fn {m, _} -> m end) |> inspect()
        {:ok, %{output: "Impossible de créer le rendez-vous : #{msgs}", action: "create"}}
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

    # Only schedule if the reminder time is in the future
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

  # due_on: exact date (same as todos)
  defp apply_date_filter(query, %{"due_on" => on_str}) do
    case parse_date(on_str) do
      nil -> apply_date_filter(query, %{})
      date -> date_range_filter(query, date, date)
    end
  end

  # Both bounds explicit
  defp apply_date_filter(query, %{"due_before" => before_str, "due_after" => after_str}) do
    case {parse_date(after_str), parse_date(before_str)} do
      {nil, _} -> apply_date_filter(query, %{"due_before" => before_str})
      {_, nil} -> apply_date_filter(query, %{"due_after" => after_str})
      {after_d, before_d} -> date_range_filter(query, after_d, before_d)
    end
  end

  # due_before only
  defp apply_date_filter(query, %{"due_before" => before_str}) do
    today = Date.utc_today()

    case parse_date(before_str) do
      nil ->
        apply_date_filter(query, %{})

      before ->
        if Date.compare(before, today) == :lt do
          end_dt = DateTime.new!(before, ~T[23:59:59], "Etc/UTC")
          from(t in query, where: t.starts_at <= ^end_dt)
        else
          date_range_filter(query, today, before)
        end
    end
  end

  # due_after only
  defp apply_date_filter(query, %{"due_after" => after_str}) do
    case parse_date(after_str) do
      nil ->
        apply_date_filter(query, %{})

      after_d ->
        start_dt = DateTime.new!(after_d, ~T[00:00:00], "Etc/UTC")
        from(t in query, where: t.starts_at >= ^start_dt)
    end
  end

  # Legacy: "date" param (backward compat)
  defp apply_date_filter(query, %{"date" => date_str}) when is_binary(date_str) do
    apply_date_filter(query, %{"due_on" => date_str})
  end

  # Legacy: "period" param (backward compat)
  defp apply_date_filter(query, %{"period" => "today"}) do
    today = Date.utc_today()
    date_range_filter(query, today, today)
  end

  defp apply_date_filter(query, %{"period" => "week"}) do
    today = Date.utc_today()
    date_range_filter(query, today, Date.add(today, 7))
  end

  # Default: today and future
  defp apply_date_filter(query, _params) do
    now = DateTime.utc_now()
    from(t in query, where: t.starts_at >= ^now)
  end

  defp date_range_filter(query, from_date, to_date) do
    start_dt = DateTime.new!(from_date, ~T[00:00:00], "Etc/UTC")
    end_dt = DateTime.new!(to_date, ~T[23:59:59], "Etc/UTC")
    from(t in query, where: t.starts_at >= ^start_dt and t.starts_at <= ^end_dt)
  end

  defp parse_date(nil), do: nil

  defp parse_date(date_str) when is_binary(date_str) do
    case Date.from_iso8601(date_str) do
      {:ok, date} -> date
      _ -> nil
    end
  end

  defp apply_contact_filter(query, nil, _schema), do: query

  defp apply_contact_filter(query, name, schema) do
    pattern = "%#{name}%"

    case resolve_contact_id(name, schema) do
      nil -> from(t in query, where: ilike(t.subject, ^pattern))
      id -> from(t in query, where: t.contact_id == ^id or ilike(t.subject, ^pattern))
    end
  end

  defp resolve_contact_id(nil, _schema), do: nil

  defp resolve_contact_id(name, schema) do
    words = String.split(name, ~r/\s+/, trim: true)

    query =
      Enum.reduce(words, from(c in Contact), fn word, q ->
        pattern = "%#{word}%"
        from(c in q, where: ilike(c.first_name, ^pattern) or ilike(c.last_name, ^pattern))
      end)

    case Repo.all(query, prefix: schema) do
      [contact] -> contact.id
      _ -> nil
    end
  end

  defp format_appointments([], _schema), do: "Aucun rendez-vous à venir."

  defp format_appointments(appointments, schema) do
    contact_ids =
      appointments |> Enum.map(& &1.contact_id) |> Enum.reject(&is_nil/1) |> Enum.uniq()

    names_by_id =
      if contact_ids == [] do
        %{}
      else
        Repo.all(from(c in Contact, where: c.id in ^contact_ids), prefix: schema)
        |> Map.new(fn c -> {c.id, display_name(c)} end)
      end

    "Rendez-vous à venir :\n" <>
      Enum.map_join(appointments, "\n", fn a ->
        date_str = Calendar.strftime(a.starts_at, "%d/%m/%Y à %Hh%M")
        location = if a.location, do: " (#{a.location})", else: ""

        contact =
          case Map.get(names_by_id, a.contact_id) do
            nil -> ""
            name -> " [#{name}]"
          end

        "• #{a.subject} — #{date_str}#{location}#{contact}"
      end)
  end

  defp display_name(c),
    do: [c.first_name, c.last_name] |> Enum.filter(& &1) |> Enum.join(" ")

  defp extract_subject(params) do
    params["subject"] || params["title"] || params["description"] || params["name"] || ""
  end

  @pending_timeout_seconds 15 * 60
  defp schedule_pending_timeout(pending_id, schema) do
    %{"pending_id" => pending_id, "schema_name" => schema}
    |> PendingTimeoutWorker.new(schedule_in: @pending_timeout_seconds)
    |> Oban.insert()
  end
end
