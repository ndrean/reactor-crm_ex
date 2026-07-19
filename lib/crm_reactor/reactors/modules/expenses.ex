defmodule CrmReactor.Reactors.Modules.Expenses do
  @moduledoc "Corporate expense claims CRUD with receipt photo extraction."

  alias CrmReactor.CRM.{Contact, ExecutionLog, Expense}
  alias CrmReactor.Reactors.PendingHelper
  alias CrmReactor.Repo
  import Ecto.Query

  @categories ~w(restaurant transport hébergement fournitures autre)

  def execute(%{action: "submit"} = ctx) do
    contact_id = resolve_contact_id(ctx.params["contact_name"], ctx.tenant_schema)
    attachment_key = ctx.params["_attachment_key"]

    case %Expense{}
         |> Expense.changeset(%{
           amount: parse_amount(ctx.params["amount"]),
           currency: ctx.params["currency"] || "EUR",
           expense_date: parse_date(ctx.params["date"]) || Date.utc_today(),
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

  def execute(%{action: "list"} = ctx) do
    base =
      from(e in Expense,
        where: e.created_by == ^ctx.user_id and is_nil(e.archived_at),
        order_by: [desc: e.expense_date]
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

  defp find_expenses(ctx) do
    description = ctx.params["description"] || ""
    pattern = "%#{description}%"

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
        date -> from(e in query, where: e.expense_date == ^date)
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
      date -> from(e in query, where: e.expense_date == ^date)
    end
  end

  defp format_result([]), do: "Aucune note de frais."

  defp format_result(expenses) do
    total = Enum.reduce(expenses, Decimal.new(0), fn e, acc -> Decimal.add(acc, e.amount) end)

    lines =
      Enum.map_join(expenses, "\n", fn e ->
        cat = if e.category, do: " [#{e.category}]", else: ""
        desc = if e.description, do: " — #{e.description}", else: ""
        "• #{e.amount} #{e.currency} (#{e.expense_date})#{cat}#{desc}"
      end)

    "Notes de frais (#{length(expenses)}, total #{total} EUR) :\n#{lines}"
  end

  defp expense_map(e) do
    %{
      "id" => e.id,
      "amount" => to_string(e.amount),
      "currency" => e.currency,
      "expense_date" => to_string(e.expense_date),
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
        pattern = "%#{word}%"
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
