defmodule CrmReactor.AI.QueryBuilder do
  @moduledoc """
  NL2SQL layer: asks the LLM to produce structured filter descriptors,
  then compiles them into safe parameterized Ecto queries.

  - Only used for read operations, never generates DML
  - Schema fields are derived from Ecto schemas (no drift)
  - Actual data never flows to the LLM — only the schema and the user's question
  - Output is a parameterized Ecto query, not raw SQL
  """

  alias CrmReactor.AI.Telemetry

  import Ecto.Query

  @allowed_ops ~w(= != like >= <= > <)

  @filter_prompt """
  You are a query filter generator for a CRM database. Today is <%= @today %>.

  Table: <%= @table_name %>
  Columns:
  <%= @columns_desc %>

  Given the user's query in French, produce structured filter conditions.
  Each filter has:
  - "field": one of the column names listed above (NOTHING ELSE)
  - "op": one of "=", "!=", "like", ">=", "<=", ">", "<"
  - "value": the comparison value. Use ISO 8601 for dates (e.g. "2026-06-28"). For "like", do NOT add % wildcards. For booleans, use true/false.

  Resolve relative dates against today (<%= @today %>):
  - "demain" = <%= @tomorrow %>
  - "après-demain" = <%= @day_after %>
  - "cette semaine" = >= <%= @today %> AND <= <%= @end_of_week %>

  Respond ONLY with: {"filters": [...], "sort_by": "column_name" or null, "sort_dir": "asc" or "desc"}
  No explanation. No SQL. No data.
  """

  def build_query(schema_module, user_text) do
    {table_name, fields_desc, allowed_fields} = introspect_schema(schema_module)

    today = Date.utc_today()

    prompt =
      EEx.eval_string(@filter_prompt,
        assigns: [
          today: today,
          tomorrow: Date.add(today, 1),
          day_after: Date.add(today, 2),
          end_of_week: Date.add(today, 7 - Date.day_of_week(today)),
          table_name: table_name,
          columns_desc: fields_desc
        ]
      )

    start_time = System.monotonic_time()

    case call_llm(prompt, user_text) do
      {:ok, %{"filters" => filters} = spec} ->
        case validate_filters(filters, allowed_fields) do
          :ok ->
            query = compile_query(schema_module, filters, allowed_fields)
            query = apply_sort(query, spec, allowed_fields)
            Telemetry.nl2sql_stop(start_time, %{filter_count: length(filters), rejected: 0})
            {:ok, query}

          {:error, _} = err ->
            n = filter_count(filters)

            Telemetry.nl2sql_stop(start_time, %{
              filter_count: n,
              rejected: n
            })

            err
        end

      {:error, _} = err ->
        Telemetry.nl2sql_stop(start_time, %{filter_count: 0, rejected: 0, error: true})
        err
    end
  end

  defp introspect_schema(schema_module) do
    table_name = schema_module.__schema__(:source)

    fields =
      schema_module.__schema__(:fields)
      |> Enum.reject(&(&1 == :id))
      |> Enum.map(fn field ->
        type = schema_module.__schema__(:type, field)
        {field, type}
      end)

    allowed = Enum.map(fields, fn {f, _} -> Atom.to_string(f) end)

    desc =
      Enum.map_join(fields, "\n", fn {field, type} ->
        "- #{field} (#{format_type(type)})"
      end)

    {table_name, desc, allowed}
  end

  defp format_type(:string), do: "text"
  defp format_type(:boolean), do: "boolean"
  defp format_type(:date), do: "date"
  defp format_type(:utc_datetime), do: "timestamp"
  defp format_type(:integer), do: "integer"
  defp format_type(other), do: to_string(other)

  defp call_llm(system_prompt, user_text) do
    case Application.get_env(:crm_reactor, :nl2sql_adapter) do
      nil -> call_mistral(system_prompt, user_text)
      adapter -> adapter.(system_prompt, user_text)
    end
  end

  defp call_mistral(system_prompt, user_text) do
    api_key = Application.fetch_env!(:crm_reactor, :mistral_api_key)
    mistral_url = Application.get_env(:crm_reactor, :mistral_api_url, "https://api.mistral.ai")

    case Req.post("#{mistral_url}/v1/chat/completions",
           json: %{
             model: "mistral-small-latest",
             messages: [
               %{role: "system", content: system_prompt},
               %{role: "user", content: user_text}
             ],
             response_format: %{type: "json_object"},
             temperature: 0
           },
           headers: [{"authorization", "Bearer #{api_key}"}],
           receive_timeout: 15_000
         ) do
      {:ok, %{status: 200, body: body}} ->
        [choice | _] = body["choices"]
        usage = body["usage"]

        if usage do
          Telemetry.llm_tokens(%{
            prompt_tokens: usage["prompt_tokens"] || 0,
            completion_tokens: usage["completion_tokens"] || 0,
            total_tokens: usage["total_tokens"] || 0,
            model: "mistral-small-latest",
            operation: :nl2sql
          })
        end

        case Jason.decode(choice["message"]["content"]) do
          {:ok, parsed} -> {:ok, parsed}
          {:error, _} -> {:error, "invalid JSON from Mistral LLM"}
        end

      {:ok, %{status: status}} ->
        {:error, "Mistral error #{status}"}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp validate_filters(filters, allowed_fields) when is_list(filters) do
    invalid =
      Enum.reject(filters, fn f ->
        is_binary(f["field"]) and
          f["field"] in allowed_fields and
          f["op"] in @allowed_ops
      end)

    case invalid do
      [] -> :ok
      bad -> {:error, {:rejected_filters, bad}}
    end
  end

  defp validate_filters(_, _), do: {:error, :invalid_format}

  defp compile_query(schema_module, filters, allowed_fields) do
    Enum.reduce(filters, from(s in schema_module), fn filter, query ->
      field_str = filter["field"]

      if field_str in allowed_fields do
        field = String.to_existing_atom(field_str)
        type = schema_module.__schema__(:type, field)
        value = cast_value(type, filter["value"])
        apply_condition(query, field, filter["op"], value)
      else
        # coveralls-ignore-start
        query
        # coveralls-ignore-stop
      end
    end)
  end

  defp apply_condition(query, field, "=", value),
    do: from(q in query, where: field(q, ^field) == ^value)

  defp apply_condition(query, field, "!=", value),
    do: from(q in query, where: field(q, ^field) != ^value)

  defp apply_condition(query, field, "like", value) when is_binary(value),
    do: from(q in query, where: ilike(field(q, ^field), ^"%#{value}%"))

  defp apply_condition(query, field, ">=", value),
    do: from(q in query, where: field(q, ^field) >= ^value)

  defp apply_condition(query, field, "<=", value),
    do: from(q in query, where: field(q, ^field) <= ^value)

  defp apply_condition(query, field, ">", value),
    do: from(q in query, where: field(q, ^field) > ^value)

  defp apply_condition(query, field, "<", value),
    do: from(q in query, where: field(q, ^field) < ^value)

  defp apply_sort(query, %{"sort_by" => field, "sort_dir" => "desc"}, allowed)
       when is_binary(field) and field != "" do
    if field in allowed,
      do: from(q in query, order_by: [desc: field(q, ^String.to_existing_atom(field))]),
      else: query
  end

  defp apply_sort(query, %{"sort_by" => field}, allowed)
       when is_binary(field) and field != "" do
    if field in allowed,
      do: from(q in query, order_by: [asc: field(q, ^String.to_existing_atom(field))]),
      else: query
  end

  defp apply_sort(query, _, _), do: query

  defp cast_value(:date, value) when is_binary(value) do
    case Date.from_iso8601(value) do
      {:ok, date} -> date
      _ -> value
    end
  end

  defp cast_value(:utc_datetime, value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, dt, _} -> dt
      _ -> value
    end
  end

  defp cast_value(:boolean, true), do: true
  defp cast_value(:boolean, false), do: false
  defp cast_value(:boolean, "true"), do: true
  defp cast_value(:boolean, "false"), do: false

  defp cast_value(:integer, value) when is_integer(value), do: value

  defp cast_value(:integer, value) when is_binary(value) do
    case Integer.parse(value) do
      {n, _} -> n
      :error -> value
    end
  end

  defp cast_value(_, value), do: value

  defp filter_count(filters) when is_list(filters), do: length(filters)
  defp filter_count(_), do: 0
end
