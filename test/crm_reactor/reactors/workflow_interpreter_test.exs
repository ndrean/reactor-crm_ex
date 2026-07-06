defmodule CrmReactor.Reactors.WorkflowInterpreterTest do
  use ExUnit.Case, async: true

  alias CrmReactor.Reactors.WorkflowInterpreter

  # ---------------------------------------------------------------------------
  # Mock modules

  defmodule MockContacts do
    def execute(%{action: "create", params: params}) do
      {:ok,
       %{
         output: "Contact créé : #{params["first_name"]} #{params["last_name"]}",
         action: "create",
         data: %{
           "contact_id" => "uuid-123",
           "first_name" => params["first_name"],
           "last_name" => params["last_name"] || ""
         }
       }}
    end

    def execute(%{action: "search"}) do
      contacts = [
        %{"id" => "uuid-1", "first_name" => "Alice", "last_name" => "Martin"},
        %{"id" => "uuid-2", "first_name" => "Bob", "last_name" => "Martin"}
      ]

      {:ok,
       %{
         output: "Voici les contacts : Alice Martin, Bob Martin",
         action: "search",
         data: %{"contacts" => contacts, "count" => 2}
       }}
    end
  end

  defmodule MockTodos do
    def execute(%{action: "create", params: params}) do
      contact_name = params["contact_name"] || ""

      {:ok,
       %{
         output: "Tâche créée : #{params["subject"]} — #{contact_name}",
         action: "create",
         data: %{"todo_id" => "todo-uuid", "subject" => params["subject"], "contact_id" => nil}
       }}
    end
  end

  defmodule MockPendingContacts do
    def execute(%{action: "delete"}) do
      {:ok,
       %{
         output: "Confirmez-vous la suppression ?",
         action: "pending",
         pending_id: "pend-123"
       }}
    end
  end

  defmodule MockManyContacts do
    def execute(%{action: "search"}) do
      contacts =
        Enum.map(1..4, fn i ->
          %{"id" => "id-#{i}", "first_name" => "Contact#{i}", "last_name" => ""}
        end)

      {:ok,
       %{
         output: "4 contacts trouvés",
         action: "search",
         data: %{"contacts" => contacts, "count" => 4}
       }}
    end
  end

  @module_map %{
    "contacts" => MockContacts,
    "todos" => MockTodos,
    "pending_contacts" => MockPendingContacts,
    "many_contacts" => MockManyContacts
  }

  @context %{
    tenant_schema: "test",
    company_name: "Test Corp",
    admin_email: nil,
    channel: :http,
    user_id: "user-1",
    log_id: 1,
    raw_text: "test"
  }

  defp step(opts) do
    %{
      id: opts[:id] || "step_1",
      workflow: opts[:workflow] || "contacts",
      action: opts[:action] || "search",
      params: opts[:params] || %{},
      routing_path: "deterministic",
      depends_on: opts[:depends_on] || [],
      for_each: opts[:for_each],
      map_param: opts[:map_param]
    }
  end

  # ---------------------------------------------------------------------------
  # Tests

  test "single step — passes through unchanged" do
    steps = [step(id: "s", workflow: "contacts", action: "search")]
    {:ok, result} = WorkflowInterpreter.run(steps, @module_map, @context)
    assert result.action == "search"
    assert result.output =~ "Alice"
  end

  test "dependent step — resolves $ref in params" do
    steps = [
      step(
        id: "c",
        workflow: "contacts",
        action: "create",
        params: %{"first_name" => "Jean", "last_name" => "Dupont"}
      ),
      step(
        id: "t",
        workflow: "todos",
        action: "create",
        params: %{
          "subject" => "Appeler",
          "contact_name" => "$c.data.first_name $c.data.last_name"
        },
        depends_on: ["c"]
      )
    ]

    {:ok, result} = WorkflowInterpreter.run(steps, @module_map, @context)
    assert result.output =~ "Contact créé"
    assert result.output =~ "Tâche créée"
    assert result.output =~ "Jean Dupont"
  end

  test "dependent step with string interpolation resolves both $refs" do
    steps = [
      step(
        id: "c",
        workflow: "contacts",
        action: "create",
        params: %{"first_name" => "Marie", "last_name" => "Curie"}
      ),
      step(
        id: "t",
        workflow: "todos",
        action: "create",
        params: %{
          "subject" => "Contacter $c.data.first_name",
          "contact_name" => "$c.data.first_name $c.data.last_name"
        },
        depends_on: ["c"]
      )
    ]

    {:ok, result} = WorkflowInterpreter.run(steps, @module_map, @context)
    assert result.output =~ "Marie Curie"
    assert result.output =~ "Contacter Marie"
  end

  test "topological sort — step with depends_on runs after its dependency regardless of list order" do
    # t listed before c, but depends on c
    steps = [
      step(
        id: "t",
        workflow: "todos",
        action: "create",
        params: %{
          "subject" => "Appeler",
          "contact_name" => "$c.data.first_name $c.data.last_name"
        },
        depends_on: ["c"]
      ),
      step(
        id: "c",
        workflow: "contacts",
        action: "create",
        params: %{"first_name" => "Jean", "last_name" => "Dupont"}
      )
    ]

    {:ok, result} = WorkflowInterpreter.run(steps, @module_map, @context)
    # $c.data.* resolved correctly means c ran first
    assert result.output =~ "Jean Dupont"
  end

  test "fan-out below threshold — runs N times and combines output" do
    steps = [
      step(id: "s", workflow: "contacts", action: "search"),
      step(
        id: "r",
        workflow: "todos",
        action: "create",
        params: %{"subject" => "Rappel"},
        depends_on: ["s"],
        for_each: "$s.data.contacts",
        map_param: "contact_name"
      )
    ]

    {:ok, result} = WorkflowInterpreter.run(steps, @module_map, @context)
    # 2 contacts → 2 todo creates
    assert result.action == "create"
    occurrences = result.output |> String.split("Tâche créée") |> length()
    # 3 parts = 2 occurrences of "Tâche créée"
    assert occurrences == 3
  end

  test "fan-out above threshold — returns clarify" do
    steps = [
      step(id: "s", workflow: "many_contacts", action: "search"),
      step(
        id: "r",
        workflow: "todos",
        action: "create",
        params: %{"subject" => "Rappel"},
        depends_on: ["s"],
        for_each: "$s.data.contacts",
        map_param: "contact_name"
      )
    ]

    {:ok, result} = WorkflowInterpreter.run(steps, @module_map, @context)
    assert result.action == "clarify"
    assert result.output =~ "4"
    assert result.output =~ "Confirmez"
  end

  test "pending step halts — later steps do not run" do
    steps = [
      step(id: "p", workflow: "pending_contacts", action: "delete"),
      step(
        id: "t",
        workflow: "todos",
        action: "create",
        params: %{"subject" => "After pending"}
      )
    ]

    {:ok, result} = WorkflowInterpreter.run(steps, @module_map, @context)
    assert result.action == "pending"
    refute result.output =~ "After pending"
  end

  test "backwards-compatible — steps without id/depends_on run as before" do
    # Old-format steps without new fields
    steps = [
      %{workflow: "contacts", action: "search", params: %{}, routing_path: "deterministic"},
      %{
        workflow: "todos",
        action: "create",
        params: %{"subject" => "Task"},
        routing_path: "deterministic"
      }
    ]

    {:ok, result} = WorkflowInterpreter.run(steps, @module_map, @context)
    assert result.output =~ "contacts"
    assert result.output =~ "Tâche créée"
  end

  test "empty for_each list — logs warning and returns empty result" do
    defmodule MockEmptySearch do
      def execute(%{action: "search"}) do
        {:ok, %{output: "0 contacts", action: "search", data: %{"contacts" => [], "count" => 0}}}
      end
    end

    steps = [
      step(id: "s", workflow: "empty_search", action: "search"),
      step(
        id: "r",
        workflow: "todos",
        action: "create",
        params: %{"subject" => "Rappel"},
        depends_on: ["s"],
        for_each: "$s.data.contacts",
        map_param: "contact_name"
      )
    ]

    module_map = Map.put(@module_map, "empty_search", MockEmptySearch)

    {:ok, result} = WorkflowInterpreter.run(steps, module_map, @context)
    assert result.action == "none"
    assert result.output =~ "Aucun"
  end

  test "unknown workflow returns helpful fallback message" do
    steps = [step(id: "s", workflow: "unknown_module", action: "search")]
    {:ok, result} = WorkflowInterpreter.run(steps, @module_map, @context)
    assert result.action == "none"
    assert result.output =~ "contacts"
  end

  test "format_item with first_name only (no last_name)" do
    defmodule MockFirstNameOnly do
      def execute(%{action: "search"}) do
        contacts = [%{"first_name" => "Alice"}]

        {:ok,
         %{output: "1 contact", action: "search", data: %{"contacts" => contacts, "count" => 1}}}
      end
    end

    steps = [
      step(id: "s", workflow: "first_name_search", action: "search"),
      step(
        id: "r",
        workflow: "todos",
        action: "create",
        params: %{"subject" => "Rappel"},
        depends_on: ["s"],
        for_each: "$s.data.contacts",
        map_param: "contact_name"
      )
    ]

    module_map = Map.put(@module_map, "first_name_search", MockFirstNameOnly)
    {:ok, result} = WorkflowInterpreter.run(steps, module_map, @context)
    assert result.output =~ "Alice"
  end

  test "format_item with binary string item" do
    defmodule MockStringItems do
      def execute(%{action: "search"}) do
        {:ok,
         %{
           output: "items",
           action: "search",
           data: %{"contacts" => ["item-a", "item-b"], "count" => 2}
         }}
      end
    end

    steps = [
      step(id: "s", workflow: "string_search", action: "search"),
      step(
        id: "r",
        workflow: "todos",
        action: "create",
        params: %{"subject" => "Task"},
        depends_on: ["s"],
        for_each: "$s.data.contacts",
        map_param: "contact_name"
      )
    ]

    module_map = Map.put(@module_map, "string_search", MockStringItems)
    {:ok, result} = WorkflowInterpreter.run(steps, module_map, @context)
    assert result.output =~ "item-a"
  end

  test "resolve_ref with non-$ prefix returns empty list (fan-out skips)" do
    defmodule MockLiteralRef do
      def execute(%{action: "search"}) do
        {:ok, %{output: "found", action: "search", data: %{"contacts" => ["x"], "count" => 1}}}
      end
    end

    steps = [
      step(id: "s", workflow: "literal_search", action: "search"),
      step(
        id: "r",
        workflow: "todos",
        action: "create",
        params: %{"subject" => "Task"},
        depends_on: ["s"],
        for_each: "not_a_ref",
        map_param: "contact_name"
      )
    ]

    module_map = Map.put(@module_map, "literal_search", MockLiteralRef)
    {:ok, result} = WorkflowInterpreter.run(steps, module_map, @context)
    # Empty for_each → "none" action with "Aucun élément"
    assert result.action == "none"
  end

  test "collect_output with no steps returns empty result" do
    {:ok, result} = WorkflowInterpreter.run([], @module_map, @context)
    assert result.output == ""
    assert result.action == "none"
  end
end
