defmodule CrmReactor.Reactors.Modules.Todos do
  @moduledoc "Task items CRUD with deterministic and NL2SQL list paths."

  alias CrmReactor.AI.{QueryBuilder, Telemetry}
  alias CrmReactor.CRM.{Contact, ExecutionLog, Todo}
  alias CrmReactor.Repo
  alias CrmReactor.Workers.PendingTimeoutWorker
  import Ecto.Query

  require Logger

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

            todos = Repo.all(query, prefix: ctx.tenant_schema)

            {:ok,
             %{
               output: format_result(todos, ctx.tenant_schema),
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

        schedule_pending_timeout(log.pending_id)
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

  def execute(%{action: action}) do
    {:ok, %{output: "Action todos non supportée : #{action}", action: action}}
  end

  # Shared lookup for complete / update / delete: subject ILIKE + optional contact.
  # due_date is intentionally excluded — for update it is the new value, not a search filter;
  # complete and delete don't include due_date in their params schema.
  # Returns list of matching todos, preferring exact subject matches over partial ones.
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

  defp execute_deterministic_list(params, contact_name, schema, user_id, contact) do
    base = from(t in Todo, where: t.done == false and t.created_by == ^user_id)
    base = apply_contact_filter(base, contact_name, contact)
    base = apply_date_filters(base, params)
    todos = Repo.all(from(t in base, order_by: t.due_date), prefix: schema)
    {:ok, %{output: format_result(todos, schema), action: "list", data: todos_data(todos)}}
  end

  # due_on: exact date, takes priority over any other date param
  defp apply_date_filters(query, %{"due_on" => on_str}) do
    case parse_date(on_str) do
      nil -> apply_date_filters(query, %{})
      on -> from(t in query, where: t.due_date == ^on)
    end
  end

  # Both bounds explicit (must appear before single-key heads)
  defp apply_date_filters(query, %{"due_before" => before_str, "due_after" => after_str}) do
    before = parse_date(before_str)
    after_ = parse_date(after_str)
    from(t in query, where: t.due_date >= ^after_ and t.due_date <= ^before)
  end

  # due_before only — past ("tâches passées") or bounded future (lower bound defaults to today)
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

  # due_after only
  defp apply_date_filters(query, %{"due_after" => after_str}) do
    case parse_date(after_str) do
      nil -> apply_date_filters(query, %{})
      after_ -> from(t in query, where: t.due_date >= ^after_)
    end
  end

  # No date params: default — today and future, including tasks with no deadline
  defp apply_date_filters(query, _params) do
    today = Date.utc_today()
    from(t in query, where: is_nil(t.due_date) or t.due_date >= ^today)
  end

  # apply_contact_filter/3 — two modes:
  #   (query, name, schema)           — resolves internally; used by complete/update/delete
  #   (query, name, contact_result)   — pre-resolved; used by list paths

  defp apply_contact_filter(query, nil, _), do: query

  # Pre-resolved: no contact_name → pass through
  defp apply_contact_filter(query, _name, :all), do: query

  # Pre-resolved: contact not in DB → subject text search
  defp apply_contact_filter(query, name, :not_found) do
    pattern = "%#{name}%"
    from(t in query, where: ilike(t.subject, ^pattern))
  end

  # Pre-resolved: unique contact found → filter by contact_id OR subject
  defp apply_contact_filter(query, name, {:found, contact_id}) do
    pattern = "%#{name}%"
    from(t in query, where: t.contact_id == ^contact_id or ilike(t.subject, ^pattern))
  end

  # Schema string: resolve internally (used by complete/update/delete)
  defp apply_contact_filter(query, name, schema) when is_binary(schema) do
    pattern = "%#{name}%"

    case resolve_contact_id(name, schema) do
      nil -> from(t in query, where: ilike(t.subject, ^pattern))
      id -> from(t in query, where: t.contact_id == ^id or ilike(t.subject, ^pattern))
    end
  end

  # resolve_contact/2 — for list paths: returns :all, {:found, id}, :not_found, or {:ambiguous, names}
  defp resolve_contact(nil, _schema), do: :all

  defp resolve_contact(name, schema) do
    words = String.split(name, ~r/\s+/, trim: true)

    query =
      Enum.reduce(words, from(c in Contact), fn word, q ->
        pattern = "%#{word}%"
        from c in q, where: ilike(c.first_name, ^pattern) or ilike(c.last_name, ^pattern)
      end)

    case Repo.all(query, prefix: schema) do
      [contact] ->
        {:found, contact.id}

      [] ->
        :not_found

      contacts ->
        {:ambiguous, Enum.map(contacts, &display_name/1)}
    end
  end

  # resolve_contact_id/2 — simple version for create (just the id, nil if not unique)
  defp resolve_contact_id(nil, _schema), do: nil

  defp resolve_contact_id(name, schema) do
    case resolve_contact(name, schema) do
      {:found, id} -> id
      _ -> nil
    end
  end

  defp disambiguation_result(name, names) do
    %{
      output:
        "Plusieurs contacts correspondent à « #{name} » : #{Enum.join(names, ", ")}. " <>
          "Précisez le nom complet.",
      action: "list",
      data: %{"todos" => [], "count" => 0}
    }
  end

  defp format_result([], _schema), do: "Aucune tâche en cours."

  defp format_result(todos, schema) do
    contact_ids = todos |> Enum.map(& &1.contact_id) |> Enum.reject(&is_nil/1) |> Enum.uniq()

    names_by_id =
      if contact_ids == [] do
        %{}
      else
        Repo.all(from(c in Contact, where: c.id in ^contact_ids), prefix: schema)
        |> Map.new(fn c -> {c.id, display_name(c)} end)
      end

    "Tâches en cours :\n" <> format_todos(todos, names_by_id)
  end

  defp format_todos(todos, names_by_id) do
    Enum.map_join(todos, "\n", fn t ->
      due = if t.due_date, do: " (#{t.due_date})", else: ""

      contact =
        case Map.get(names_by_id, t.contact_id) do
          nil -> ""
          name -> " [#{name}]"
        end

      "• #{t.subject}#{contact}#{due}"
    end)
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

  @pending_timeout_seconds 15 * 60
  defp schedule_pending_timeout(pending_id) do
    %{"pending_id" => pending_id}
    |> PendingTimeoutWorker.new(schedule_in: @pending_timeout_seconds)
    |> Oban.insert()
  end
end
