defmodule CrmReactor.AI.MockClassifier do
  @moduledoc "Regex-based mock classifier for fast tests without API calls."
  @behaviour CrmReactor.AI.ClassifierBehaviour

  @impl true
  def classify_workflow(_text, _registry, hints) do
    {workflow, _score} = List.first(hints, {"contacts", 0.9})
    {:ok, {workflow, 0.90, %{prompt_tokens: 50, completion_tokens: 10, total_tokens: 60}}}
  end

  @impl true
  def classify_with_file(instruction, _file_content, _content_type, registry) do
    classify(instruction, registry)
  end

  @impl true
  def classify(text, registry, _routing_hint), do: classify(text, registry)

  @impl true
  def classify(text, registry, _routing_hint, _context), do: classify(text, registry)

  @impl true
  def classify(text, _registry) do
    steps = classify_steps(text)

    {:ok,
     %{
       steps: steps,
       prompt_tokens: 100,
       completion_tokens: 30,
       total_tokens: 130
     }}
  end

  defp classify_steps(text) do
    text_down = String.downcase(text)

    # Multi-intent: two action verbs separated by "et" → return 2 fixed steps
    if text_down =~ ~r/(ajoute|crée|supprime|modifie).+\bet\b.+(ajoute|crée|supprime|modifie)/ do
      [
        %{
          workflow: "contacts",
          action: "create",
          params: %{"first_name" => "Jean", "last_name" => "Dupont"},
          routing_path: "deterministic"
        },
        %{
          workflow: "todos",
          action: "create",
          params: %{
            "subject" => "Appeler Jean",
            "contact_name" => "Jean Dupont",
            "due_date" => to_string(Date.add(Date.utc_today(), 1))
          },
          routing_path: "deterministic"
        }
      ]
    else
      [single_step(text_down, text)]
    end
  end

  defp single_step(text_down, original_text) do
    step =
      patterns()
      |> Enum.find(fn {pattern, _, _, _} -> text_down =~ pattern end)
      |> case do
        {_, workflow, action, params_fn} ->
          %{workflow: workflow, action: action, params: params_fn.(original_text)}

        nil ->
          %{workflow: "none", action: "none", params: %{}}
      end

    Map.put(step, :routing_path, "deterministic")
  end

  defp patterns do
    [
      {~r/cherche|trouve|affiche.*contact/, "contacts", "search", &extract_name/1},
      {~r/combien.*contact/, "contacts", "count", fn _ -> %{} end},
      {~r/supprime.*contact|supprime\s+\w/, "contacts", "delete", &extract_name/1},
      {~r/modifie.*contact/, "contacts", "update", &extract_name/1},
      {~r/crée.*tâche|ajoute.*tâche/, "todos", "create",
       fn _ ->
         %{"subject" => "Nouvelle tâche", "due_date" => to_string(Date.add(Date.utc_today(), 1))}
       end},
      {~r/liste.*tâche|affiche.*tâche|mes tâches/, "todos", "list", fn _ -> %{} end},
      {~r/termine|complète/, "todos", "complete",
       fn text -> %{"subject" => extract_after(text, ~r/termine|complète/)} end},
      {~r/rendez-vous|réunion|rdv|créneau|planifi/i, "appointments", "create",
       fn _ ->
         tomorrow = Date.add(Date.utc_today(), 1) |> Date.to_iso8601()
         %{"subject" => "Réunion test", "date" => tomorrow, "time" => "14:00"}
       end},
      {~r/mes rendez-vous|prochains? rdv|agenda/i, "appointments", "list", fn _ -> %{} end},
      {~r/annule.*rdv|annule.*rendez-vous|annule.*réunion/i, "appointments", "cancel",
       fn text -> %{"subject" => extract_after(text, ~r/annule/)} end},
      {~r/déplace|reporte|reprogramme/i, "appointments", "reschedule",
       fn text -> %{"subject" => extract_after(text, ~r/déplace|reporte|reprogramme/)} end},
      {~r/exporte|rapport/, "data", "dump", fn _ -> %{} end}
    ]
  end

  defp extract_name(text) do
    %{"search_name" => extract_after(text, ~r/cherche|trouve|affiche|supprime|modifie/)}
  end

  defp extract_after(text, pattern) do
    case Regex.split(pattern, text, parts: 2) do
      [_, rest] -> String.trim(rest)
      _ -> text
    end
  end
end
