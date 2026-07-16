defmodule CrmReactor.Reactors.WorkflowInterpreter do
  @moduledoc """
  Variable-threaded sequential executor for multi-step LLM plans.

  Supports:
  - Topological ordering via `depends_on`
  - `$step_id.data.field` variable resolution in params
  - Fan-out execution via `for_each` + `map_param`
  - Fan-out confirmation guard above threshold
  """

  require Logger

  @fanout_confirm_threshold 3

  @doc """
  Run a list of steps, resolving dependencies and variable references.
  Returns `{:ok, combined_result}` or `{:error, reason}`.
  """
  def run(steps, module_map, context) do
    normalized = Enum.map(steps, &normalize_step/1)
    sorted = topological_sort(normalized)

    if length(sorted) != length(normalized) do
      {:error, :cyclical_dependency}
    else
      run_sorted(sorted, normalized, module_map, context)
    end
  end

  defp run_sorted(sorted, normalized, module_map, context) do
    Enum.reduce_while(sorted, {:ok, %{}, MapSet.new()}, fn step, {:ok, env, failed} ->
      execute_or_skip(step, env, failed, module_map, context)
    end)
    |> then(fn {:ok, env, _failed} -> {:ok, env} end)
    |> collect_output(normalized)
  end

  defp execute_or_skip(step, env, failed, module_map, context) do
    if Enum.any?(step.depends_on, &MapSet.member?(failed, &1)) do
      Logger.warning("Skipping step #{step.id}: dependency failed")
      {:cont, {:ok, env, MapSet.put(failed, step.id)}}
    else
      resolved_params = resolve_refs(step.params, env)

      case run_step(%{step | params: resolved_params}, env, module_map, context) do
        {:ok, %{action: action} = r} when action in ~w(pending clarify) ->
          {:halt, {:ok, Map.put(env, step.id, r), failed}}

        {:ok, r} ->
          {:cont, {:ok, Map.put(env, step.id, r), failed}}

        {:error, reason} ->
          Logger.warning("Step #{step.id} failed: #{inspect(reason)}, continuing pipeline")
          error_result = %{output: "Erreur lors de l'étape #{step.id}.", action: "error"}
          {:cont, {:ok, Map.put(env, step.id, error_result), MapSet.put(failed, step.id)}}
      end
    end
  end

  # ---------------------------------------------------------------------------
  # Step normalization — ensures all fields exist for backwards compatibility

  defp normalize_step(step) do
    step
    |> Map.put_new(:id, generate_step_id())
    |> Map.put_new(:depends_on, [])
    |> Map.put_new(:for_each, nil)
    |> Map.put_new(:map_param, nil)
  end

  defp generate_step_id, do: "step_#{:erlang.unique_integer([:positive, :monotonic])}"

  # ---------------------------------------------------------------------------
  # Topological sort (Kahn's algorithm)

  defp topological_sort(steps) do
    step_ids = MapSet.new(steps, & &1.id)
    {in_degree, adj} = Enum.reduce(steps, {%{}, %{}}, &build_edges(&1, &2, step_ids))

    initial_queue =
      steps
      |> Enum.filter(fn s -> Map.get(in_degree, s.id, 0) == 0 end)
      |> Enum.map(& &1.id)

    steps_by_id = Map.new(steps, fn s -> {s.id, s} end)
    do_kahn(initial_queue, in_degree, adj, steps_by_id, [])
  end

  defp build_edges(step, {in_deg, adj}, step_ids) do
    in_deg = Map.put_new(in_deg, step.id, 0)
    valid_deps = Enum.filter(step.depends_on, &MapSet.member?(step_ids, &1))
    Enum.reduce(valid_deps, {in_deg, adj}, &add_edge(&1, step.id, &2))
  end

  defp add_edge(dep, step_id, {in_deg, adj}) do
    {Map.update(in_deg, step_id, 1, &(&1 + 1)), Map.update(adj, dep, [step_id], &[step_id | &1])}
  end

  defp do_kahn([], _in_degree, _adj, _steps_by_id, result), do: Enum.reverse(result)

  defp do_kahn([id | queue], in_degree, adj, steps_by_id, result) do
    step = Map.fetch!(steps_by_id, id)

    {new_in_degree, newly_unblocked} =
      Map.get(adj, id, [])
      |> Enum.reduce({in_degree, []}, fn dep_id, {in_deg, unblocked} ->
        new_count = Map.get(in_deg, dep_id, 0) - 1
        in_deg = Map.put(in_deg, dep_id, new_count)
        unblocked = if new_count == 0, do: [dep_id | unblocked], else: unblocked
        {in_deg, unblocked}
      end)

    do_kahn(queue ++ Enum.reverse(newly_unblocked), new_in_degree, adj, steps_by_id, [
      step | result
    ])
  end

  # ---------------------------------------------------------------------------
  # Step execution — plain vs fan-out

  defp run_step(%{for_each: ref} = step, env, module_map, context) when not is_nil(ref) do
    items = resolve_ref(ref, env)

    if items == [] do
      Logger.warning(
        "WorkflowInterpreter: for_each ref #{inspect(ref)} resolved to empty list. " <>
          "Check that the referenced step id exists and produced data. " <>
          "Step: #{inspect(step.id)}, env keys: #{inspect(Map.keys(env))}"
      )
    end

    n = length(items)

    if n > @fanout_confirm_threshold do
      formatted_items = Enum.map(items, &format_item/1)

      {:ok,
       %{
         output: "Je vais exécuter #{n} opérations (#{step.action}). Confirmez ?",
         action: "clarify",
         confirm_items: formatted_items,
         confirm_step: %{
           "workflow" => step.workflow,
           "action" => step.action,
           "params" => step.params,
           "routing_path" => step.routing_path,
           "map_param" => step.map_param
         }
       }}
    else
      results =
        Enum.map(items, fn item ->
          item_params = Map.put(step.params, step.map_param, format_item(item))
          execute_module(%{step | params: item_params}, module_map, context)
        end)

      combine_fanout_results(results)
    end
  end

  defp run_step(step, _env, module_map, context) do
    execute_module(step, module_map, context)
  end

  defp execute_module(step, module_map, context) do
    case Map.get(module_map, step.workflow) do
      nil ->
        {:ok,
         %{
           output:
             "Je peux vous aider avec vos contacts, tâches et données. Que souhaitez-vous faire ?",
           action: "none"
         }}

      module ->
        module.execute(%{
          action: step.action,
          params: step.params,
          routing_path: step.routing_path,
          raw_text: context.raw_text,
          tenant_schema: context.tenant_schema,
          company_name: context.company_name,
          admin_email: context.admin_email,
          channel: context.channel,
          user_id: context.user_id,
          log_id: context.log_id
        })
    end
  end

  defp combine_fanout_results([]) do
    {:ok, %{output: "Aucun élément à traiter.", action: "none"}}
  end

  defp combine_fanout_results(results) do
    {oks, errors} = Enum.split_with(results, &match?({:ok, _}, &1))

    case oks do
      [] ->
        List.first(errors) || {:error, "Toutes les opérations ont échoué."}

      _ ->
        combined = Enum.map_join(oks, "\n", fn {:ok, r} -> r.output end)

        combined =
          if errors != [] do
            error_count = length(errors)
            combined <> "\n(#{error_count} opération(s) ont échoué)"
          else
            combined
          end

        {:ok, last} = List.last(oks)
        {:ok, Map.put(last, :output, combined)}
    end
  end

  defp format_item(%{"first_name" => first, "last_name" => last}), do: "#{first} #{last}"
  defp format_item(%{"first_name" => first}), do: first
  defp format_item(item) when is_binary(item), do: item
  defp format_item(item), do: to_string(item)

  # ---------------------------------------------------------------------------
  # Variable resolution

  defp resolve_refs(params, env) do
    Map.new(params, fn
      {k, v} when is_binary(v) -> {k, resolve_string(v, env)}
      {k, v} -> {k, v}
    end)
  end

  # Replaces "$c.data.first_name $c.data.last_name" → "Jean Dupont"
  defp resolve_string(v, env) do
    Regex.replace(~r/\$([a-z_][a-z0-9_.]*)/i, v, fn _, path ->
      parts = String.split(path, ".")

      case get_nested(env, parts) do
        nil -> ""
        value -> to_string(value)
      end
    end)
  end

  defp resolve_ref("$" <> path, env) do
    parts = String.split(path, ".")
    get_nested(env, parts) || []
  end

  defp resolve_ref(_, _), do: []

  # Walks a nested map, trying string keys first then atom keys.
  # Needed because module results use atom keys (:data, :output) while
  # the data payloads use string keys ("first_name", etc.).
  defp get_nested(map, [key | rest]) when is_map(map) do
    val =
      case Map.fetch(map, key) do
        {:ok, v} ->
          v

        :error ->
          atom_key =
            try do
              String.to_existing_atom(key)
            rescue
              ArgumentError -> nil
            end

          if atom_key, do: Map.get(map, atom_key), else: nil
      end

    if rest == [], do: val, else: get_nested(val, rest)
  end

  defp get_nested(_, _), do: nil

  # ---------------------------------------------------------------------------
  # Output collection

  defp collect_output({:ok, env}, steps) do
    results =
      steps
      |> Enum.map(fn s -> Map.get(env, s.id) end)
      |> Enum.reject(&is_nil/1)

    case results do
      [] ->
        {:ok, %{output: "", action: "none"}}

      [single] ->
        {:ok, single}

      many ->
        combined = Enum.map_join(many, "\n", & &1.output)
        last = List.last(many)
        {:ok, Map.put(last, :output, combined)}
    end
  end
end
