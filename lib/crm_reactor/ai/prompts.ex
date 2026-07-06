defmodule CrmReactor.AI.Prompts do
  @moduledoc "Builds LLM prompts from module registry entries."

  def build_master_prompt(registry_entries) do
    modules_desc =
      registry_entries
      |> Enum.group_by(& &1.workflow_name)
      |> Enum.map_join("\n", fn {workflow, entries} ->
        actions_desc = Enum.map_join(entries, "\n", &format_action/1)
        "- #{workflow}:\n#{actions_desc}"
      end)

    """
    <role>
    You are a JSON-only intent router for a French CRM assistant.
    Classify the user message into one or more module/action steps.
    Output ONLY a valid JSON object — no markdown, no explanation.
    </role>

    <output_format>
    Always a "steps" array, even for a single intent:
    {"steps":[{"workflow":"","action":"","params":{...},"routing_path":"deterministic"}]}

    Multiple distinct commands in one message → one step per command:
    {"steps":[{"workflow":"contacts","action":"create","params":{...},"routing_path":"deterministic"},{"workflow":"todos","action":"create","params":{...},"routing_path":"deterministic"}]}
    </output_format>

    <modules>
    #{modules_desc}

    User asks what the system can do / asks for help:
    {"steps":[{"workflow":"help","action":"help","params":{},"routing_path":"deterministic"}]}

    No module matches:
    {"steps":[{"workflow":"none","action":"none","params":{},"routing_path":"deterministic"}]}
    </modules>

    <rules>
    COMMAND vs QUESTION: "ajoute un email à Marie" → matching action. "puis-je ajouter un email ?", "que peux-tu faire ?" → "help".

    routing_path: "deterministic" for simple name/id lookups. "nl2sql" for compound filters, aggregations, or relative dates requiring resolution.

    Always extract every optional param whose value appears in the message.
    </rules>

    <examples>
    Step dependencies — create a contact then link a todo (every step MUST have an explicit "id"):
    {"steps":[
      {"id":"c","workflow":"contacts","action":"create","params":{"first_name":"Jean","last_name":"Dupont"},"routing_path":"deterministic","depends_on":[]},
      {"id":"t","workflow":"todos","action":"create","params":{"subject":"Appeler","contact_name":"$c.data.first_name $c.data.last_name","due_date":"#{Date.add(Date.utc_today(), 1)}"},"routing_path":"deterministic","depends_on":["c"]}
    ]}

    Fan-out — create a reminder for every contact found (for_each + map_param):
    {"steps":[
      {"id":"s","workflow":"contacts","action":"search","params":{"search_company":"Acme Corp"},"routing_path":"deterministic","depends_on":[]},
      {"id":"r","workflow":"todos","action":"create","params":{"subject":"Rappel client","due_date":"#{Date.add(Date.utc_today(), 7)}"},"routing_path":"deterministic","depends_on":["s"],"for_each":"$s.data.contacts","map_param":"contact_name"}
    ]}

    Rule: if step B has "depends_on":["s"], there MUST be another step with "id":"s".
    Independent steps: omit "depends_on" or leave it empty.
    Use "$step_id.data.field" to reference data from a previous step.
    </examples>

    <date_handling>
    Today is #{Date.utc_today()}. Normalize ALL dates to YYYY-MM-DD (relative: "demain", "lundi prochain"; absolute: "2/7/2026", "le 2 juillet").

    todos.list date params (due_before is INCLUSIVE):
    - "jusqu'à demain", "d'ici demain"         → due_before: #{Date.add(Date.utc_today(), 1)}
    - "tâches passées", "en retard", "overdue" → due_before: #{Date.add(Date.utc_today(), -1)}
    - "à partir de demain", "dès demain"       → due_after:  #{Date.add(Date.utc_today(), 1)}
    - "pour demain", "exactement demain"       → due_on:     #{Date.add(Date.utc_today(), 1)}
    </date_handling>
    """
  end

  def build_vision_prompt(registry_entries) do
    modules_desc =
      registry_entries
      |> Enum.group_by(& &1.workflow_name)
      |> Enum.map_join("\n", fn {workflow, entries} ->
        actions_desc = Enum.map_join(entries, "\n", &format_action/1)
        "- #{workflow}:\n#{actions_desc}"
      end)

    """
    <role>
    You are a JSON-only data extractor for a French CRM assistant.
    The user has attached a file and provided an instruction.
    Analyze the file content and the instruction to determine what CRM actions to take.
    Output ONLY a valid JSON object — no markdown, no explanation.
    </role>

    <output_format>
    Always a "steps" array, even for a single action:
    {"steps":[{"workflow":"","action":"","params":{...},"routing_path":"deterministic"}]}

    Multiple records found in the file → one step per record:
    {"steps":[
      {"workflow":"contacts","action":"create","params":{"first_name":"Jean","last_name":"Dupont","phone":"0612345678"},"routing_path":"deterministic"},
      {"workflow":"contacts","action":"create","params":{"first_name":"Marie","last_name":"Martin","email":"marie@example.com"},"routing_path":"deterministic"}
    ]}
    </output_format>

    <modules>
    #{modules_desc}

    No data can be extracted or instruction is unclear:
    {"steps":[{"workflow":"none","action":"none","params":{},"routing_path":"deterministic"}]}
    </modules>

    <rules>
    Extract ALL data visible in the file: names, emails, phones, companies, dates, etc.
    Create one step per distinct record found.
    Normalize all dates to YYYY-MM-DD. Today is #{Date.utc_today()}.
    Prefer contacts.create for people, todos.create for tasks/reminders.
    If the instruction says to search or count rather than create, use the appropriate action.
    </rules>
    """
  end

  defp format_action(e),
    do: "    * #{e.action}#{format_schema(e.params_schema)}#{format_hint(e.prompt_hint)}"

  defp format_schema(nil), do: ""

  defp format_schema(schema) do
    req = schema["required"] || []
    opt = schema["optional"] || []

    parts =
      if(req != [], do: ["required: #{Enum.join(req, ", ")}"], else: []) ++
        if opt != [], do: ["optional: #{Enum.join(opt, ", ")}"], else: []

    if parts != [], do: " [params — #{Enum.join(parts, "; ")}]", else: ""
  end

  defp format_hint(nil), do: ""
  defp format_hint(hint), do: " (#{hint})"
end
