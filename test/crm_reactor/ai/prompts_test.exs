defmodule CrmReactor.AI.PromptsTest do
  use ExUnit.Case, async: true

  alias CrmReactor.AI.Prompts

  defp entry(workflow, action, params_schema \\ nil, hint \\ nil) do
    %{workflow_name: workflow, action: action, params_schema: params_schema, prompt_hint: hint}
  end

  describe "build_master_prompt/1" do
    test "includes today's date" do
      prompt = Prompts.build_master_prompt([])
      assert prompt =~ to_string(Date.utc_today())
    end

    test "includes workflow and actions from registry" do
      entries = [
        entry("contacts", "search"),
        entry("contacts", "count"),
        entry("todos", "list")
      ]

      prompt = Prompts.build_master_prompt(entries)
      assert prompt =~ "contacts"
      assert prompt =~ "search"
      assert prompt =~ "todos"
      assert prompt =~ "list"
    end

    test "formats required and optional params" do
      entries = [
        entry("contacts", "create", %{"required" => ["first_name"], "optional" => ["phone"]})
      ]

      prompt = Prompts.build_master_prompt(entries)
      assert prompt =~ "required: first_name"
      assert prompt =~ "optional: phone"
    end

    test "required-only params schema" do
      entries = [entry("contacts", "delete", %{"required" => ["search_name"]})]
      prompt = Prompts.build_master_prompt(entries)
      assert prompt =~ "required: search_name"
      refute prompt =~ "optional:"
    end

    test "optional-only params schema" do
      entries = [entry("todos", "list", %{"optional" => ["contact_name"]})]
      prompt = Prompts.build_master_prompt(entries)
      assert prompt =~ "optional: contact_name"
      refute prompt =~ "required:"
    end

    test "nil params_schema emits no params bracket" do
      entries = [entry("help", "help")]
      prompt = Prompts.build_master_prompt(entries)
      assert byte_size(prompt) > 0
      refute prompt =~ "[params —"
    end

    test "formats prompt hint" do
      entries = [entry("todos", "list", nil, "list open tasks")]
      prompt = Prompts.build_master_prompt(entries)
      assert prompt =~ "(list open tasks)"
    end

    test "empty registry produces valid JSON format instructions" do
      prompt = Prompts.build_master_prompt([])
      assert prompt =~ ~s("steps")
      assert prompt =~ ~s("workflow")
    end

    test "multiple workflows are each listed" do
      entries = [entry("contacts", "search"), entry("data", "dump"), entry("help", "help")]
      prompt = Prompts.build_master_prompt(entries)
      assert prompt =~ "- contacts:"
      assert prompt =~ "- data:"
      assert prompt =~ "- help:"
    end
  end

  describe "build_vision_prompt/1" do
    test "includes today's date" do
      prompt = Prompts.build_vision_prompt([])
      assert prompt =~ to_string(Date.utc_today())
    end

    test "includes workflow entries" do
      entries = [entry("contacts", "create")]
      prompt = Prompts.build_vision_prompt(entries)
      assert prompt =~ "contacts"
      assert prompt =~ "create"
    end

    test "always includes steps output format" do
      prompt = Prompts.build_vision_prompt([])
      assert prompt =~ ~s("steps")
    end

    test "formats params schema same as master prompt" do
      entries = [entry("contacts", "create", %{"required" => ["first_name", "last_name"]})]
      prompt = Prompts.build_vision_prompt(entries)
      assert prompt =~ "required: first_name, last_name"
    end
  end
end
