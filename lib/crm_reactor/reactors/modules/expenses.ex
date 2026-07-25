defmodule CrmReactor.Reactors.Modules.Expenses do
  @moduledoc "Corporate expense claims CRUD with receipt photo extraction."

  alias CrmReactor.AI.{QueryBuilder, Telemetry}
  alias CrmReactor.CRM.{Contact, ExecutionLog, Expense}
  alias CrmReactor.Reactors.PendingHelper
  alias CrmReactor.Repo
  import CrmReactor.QueryHelpers, only: [ilike_pattern: 1]
  import Ecto.Query

  require Logger

  @categories ~w(restaurant transport hébergement fournitures autre)

  # ── Expenses: list (NL2SQL) ────────────────────────────────────────

  def execute(%{action: "list", routing_path: "nl2sql"} = ctx) do
    Logger.info("[Expenses] list nl2sql path, raw_text=#{inspect(ctx.raw_text)}")

    case QueryBuilder.build_query(Expense, ctx.raw_text) do
      {:ok, nl2sql_query} ->
        query =
          from(e in nl2sql_query,
            where: e.created_by == ^ctx.user_id and is_nil(e.archived_at),
            order_by: [desc: e.date]
          )

        Logger.info("[Expenses] list nl2sql final query: #{inspect(query)}")
        expenses = Repo.all(query, prefix: ctx.tenant_schema)
        Logger.info("[Expenses] list nl2sql found #{length(expenses)} expenses")

        {:ok,
         %{
           output: format_result(expenses),
           action: "list",
           data: %{"expenses" => Enum.map(expenses, &expense_map/1), "count" => length(expenses)}
         }}

      {:error, reason} ->
        Logger.warning("NL2SQL failed for expenses list: #{inspect(reason)}, falling back")
        Telemetry.nl2sql_fallback_to_deterministic(%{module: "expenses"})
        execute_deterministic_list(ctx)
    end
  end

  # ── Expenses: list (deterministic) ─────────────────────────────────

  def execute(%{action: "list"} = ctx) do
    Logger.info("[Expenses] list deterministic path, params=#{inspect(ctx.params)}")
    execute_deterministic_list(ctx)
  end

  # ── Expenses: total ────────────────────────────────────────────────

  def execute(%{action: "total"} = ctx) do
    Logger.info("[Expenses] total action, raw_text=#{inspect(ctx.raw_text)}")

    base_query =
      case QueryBuilder.build_query(Expense, ctx.raw_text) do
        {:ok, nl2sql_query} ->
          scoped =
            from(e in nl2sql_query,
              where: e.created_by == ^ctx.user_id and is_nil(e.archived_at)
            )

          Logger.info("[Expenses] total nl2sql base query: #{inspect(scoped)}")
          scoped

        {:error, reason} ->
          Logger.warning("[Expenses] total NL2SQL failed: #{inspect(reason)}, using all expenses")

          Telemetry.nl2sql_fallback_to_deterministic(%{module: "expenses"})

          from(e in Expense,
            where: e.created_by == ^ctx.user_id and is_nil(e.archived_at)
          )
      end

    agg_query =
      from(e in base_query,
        group_by: e.currency,
        select: {e.currency, sum(e.amount)}
      )

    Logger.info("[Expenses] total aggregation query: #{inspect(agg_query)}")

    totals = Repo.all(agg_query, prefix: ctx.tenant_schema)
    Logger.info("[Expenses] total result: #{inspect(totals)}")

    case totals do
      [] ->
        {:ok,
         %{
           output: "Aucune dépense trouvée.",
           action: "total",
           data: %{"totals" => %{}}
         }}

      totals ->
        totals_map =
          Map.new(totals, fn {currency, amount} -> {currency, Decimal.to_string(amount)} end)

        formatted =
          Enum.map_join(totals, ", ", fn {currency, amount} ->
            "#{Decimal.to_string(amount)} #{currency}"
          end)

        {:ok,
         %{
           output: "Total des dépenses : #{formatted}",
           action: "total",
           data: %{"totals" => totals_map}
         }}
    end
  end

  def execute(%{action: "submit"} = ctx) do
    contact_id = resolve_contact_id(ctx.params["contact_name"], ctx.tenant_schema)
    attachment_key = ctx.params["_attachment_key"]

    case %Expense{}
         |> Expense.changeset(%{
           amount: parse_amount(ctx.params["amount"]),
           currency: ctx.params["currency"] || "EUR",
           date: parse_date(ctx.params["date"]) || Date.utc_today(),
           category: normalize_category(ctx.params["category"]),
           description: ctx.params["description"],
           created_by: ctx.user_id,
           contact_id: contact_id,
           attachment_key: attachment_key
         })
         |> Repo.insert(prefix: ctx.tenant_schema) do
      {:ok, expense} ->
        cat = if expense.category, do: " [#{expense.category}]", else: ""

        {:ok,
         %{
           output: "Note de frais enregistrée : #{expense.amount} #{expense.currency}#{cat}",
           action: "submit",
           data: %{
             "expense_id" => expense.id,
             "amount" => to_string(expense.amount),
             "category" => expense.category
           }
         }}

      {:error, changeset} ->
        msgs = Ecto.Changeset.traverse_errors(changeset, fn {m, _} -> m end) |> inspect()
        {:ok, %{output: "Impossible de créer la note de frais : #{msgs}", action: "submit"}}
    end
  end

  def execute(%{action: "delete"} = ctx) do
    case find_expenses(ctx) do
      [match] ->
        log =
          Repo.get!(ExecutionLog, ctx.log_id, prefix: ctx.tenant_schema)
          |> ExecutionLog.pending_changeset(%{
            action: "delete",
            module: "expenses",
            proposed_params: %{"expense_id" => match.id}
          })
          |> Repo.update!(prefix: ctx.tenant_schema)

        schedule_pending_timeout(log.pending_id, ctx.tenant_schema)

        {:ok,
         %{
           output:
             "Confirmez-vous la suppression de la note de frais « #{match.description || to_string(match.amount)} » ?",
           action: "pending",
           pending_type: "confirm",
           pending_id: log.pending_id
         }}

      [] ->
        {:ok, %{output: "Aucune note de frais trouvée.", action: "delete"}}

      _many ->
        {:ok, %{output: "Plusieurs notes de frais correspondent. Précisez.", action: "delete"}}
    end
  end

  def execute(%{action: action}) do
    {:ok, %{output: "Action expenses non supportée : #{action}", action: action}}
  end

  # --- Private ---

  defp execute_deterministic_list(ctx) do
    base =
      from(e in Expense,
        where: e.created_by == ^ctx.user_id and is_nil(e.archived_at),
        order_by: [desc: e.date]
      )

    base = apply_filters(base, ctx.params)
    expenses = Repo.all(base, prefix: ctx.tenant_schema)

    {:ok,
     %{
       output: format_result(expenses),
       action: "list",
       data: %{"expenses" => Enum.map(expenses, &expense_map/1), "count" => length(expenses)}
     }}
  end

  defp find_expenses(ctx) do
    description = ctx.params["description"] || ""
    pattern = ilike_pattern(description)

    query =
      from(e in Expense,
        where:
          e.created_by == ^ctx.user_id and ilike(e.description, ^pattern) and
            is_nil(e.archived_at)
      )

    query =
      case parse_amount(ctx.params["amount"]) do
        nil -> query
        amount -> from(e in query, where: e.amount == ^amount)
      end

    query =
      case parse_date(ctx.params["date"]) do
        nil -> query
        date -> from(e in query, where: e.date == ^date)
      end

    Repo.all(query, prefix: ctx.tenant_schema)
  end

  defp apply_filters(query, params) do
    query
    |> filter_category(params["category"])
    |> filter_status(params["status"])
    |> filter_date(params["date"])
  end

  defp filter_category(query, nil), do: query
  defp filter_category(query, cat), do: from(e in query, where: e.category == ^cat)

  defp filter_status(query, nil), do: query
  defp filter_status(query, status), do: from(e in query, where: e.status == ^status)

  defp filter_date(query, nil), do: query

  defp filter_date(query, date_str) do
    case parse_date(date_str) do
      nil -> query
      date -> from(e in query, where: e.date == ^date)
    end
  end

  defp format_result([]), do: "Aucune note de frais."

  defp format_result(expenses) do
    totals_by_currency =
      expenses
      |> Enum.group_by(& &1.currency, & &1.amount)
      |> Enum.map_join(", ", fn {currency, amounts} ->
        total = Enum.reduce(amounts, Decimal.new(0), &Decimal.add/2)
        "#{total} #{currency}"
      end)

    lines =
      Enum.map_join(expenses, "\n", fn e ->
        cat = if e.category, do: " [#{e.category}]", else: ""
        desc = if e.description, do: " — #{e.description}", else: ""
        "• #{e.amount} #{e.currency} (#{e.date})#{cat}#{desc}"
      end)

    "Notes de frais (#{length(expenses)}, total #{totals_by_currency}) :\n#{lines}"
  end

  defp expense_map(e) do
    %{
      "id" => e.id,
      "amount" => to_string(e.amount),
      "currency" => e.currency,
      "date" => to_string(e.date),
      "category" => e.category,
      "description" => e.description,
      "status" => e.status
    }
  end

  defp parse_amount(nil), do: nil

  defp parse_amount(val) when is_binary(val) do
    normalized = String.replace(val, ",", ".")

    case Decimal.parse(normalized) do
      {decimal, _} -> decimal
      :error -> nil
    end
  end

  defp parse_amount(val) when is_number(val), do: Decimal.new(to_string(val))

  defp parse_date(nil), do: nil

  defp parse_date(date_str) when is_binary(date_str) do
    case Date.from_iso8601(date_str) do
      {:ok, date} -> date
      _ -> nil
    end
  end

  defp normalize_category(nil), do: nil

  defp normalize_category(cat) do
    downcased = String.downcase(cat)
    if downcased in @categories, do: downcased, else: "autre"
  end

  defp resolve_contact_id(nil, _schema), do: nil

  defp resolve_contact_id(name, schema) do
    words = String.split(name, ~r/\s+/, trim: true)

    query =
      Enum.reduce(words, from(c in Contact), fn word, q ->
        pattern = ilike_pattern(word)
        from c in q, where: ilike(c.first_name, ^pattern) or ilike(c.last_name, ^pattern)
      end)

    case Repo.all(query, prefix: schema) do
      [contact] -> contact.id
      _ -> nil
    end
  end

  defp schedule_pending_timeout(pending_id, schema),
    do: PendingHelper.schedule_pending_timeout(pending_id, schema)
end
