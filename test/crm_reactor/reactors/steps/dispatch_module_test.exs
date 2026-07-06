defmodule CrmReactor.Reactors.Steps.DispatchModuleTest do
  use CrmReactor.DataCase

  alias CrmReactor.Reactors.Steps.DispatchModule
  alias CrmReactor.TestFixtures

  setup do
    fixture = TestFixtures.provision_test_tenant()
    on_exit(fn -> TestFixtures.cleanup_tenant(fixture) end)
    fixture
  end

  defp args(workflow, action, params \\ %{}, tenant \\ nil) do
    %{
      classification: %{
        steps: [
          %{workflow: workflow, action: action, params: params, routing_path: "deterministic"}
        ],
        prompt_tokens: 100,
        completion_tokens: 30,
        total_tokens: 130
      },
      tenant: tenant || %{schema_name: nil, company_name: "Test", admin_email: nil},
      channel: :http,
      user_id: "test-user",
      log: %{id: 0},
      text: "test input"
    }
  end

  test "unknown workflow returns help message" do
    {:ok, result} = DispatchModule.run(args("unknown", "none"), %{}, [])
    assert result.action == "none"
    assert result.output =~ "contacts"
  end

  test "missing workflow key also returns help message" do
    {:ok, result} = DispatchModule.run(args("xyzzy", "anything"), %{}, [])
    assert result.action == "none"
  end

  test "contacts search routes to Contacts module", %{tenant: tenant} do
    {:ok, result} =
      DispatchModule.run(
        args("contacts", "count", %{}, %{
          schema_name: tenant.schema_name,
          company_name: tenant.company_name,
          admin_email: tenant.admin_email
        }),
        %{},
        []
      )

    assert result.action == "count"
    assert result.output =~ "2"
  end

  test "multi-step with multiple destructive actions returns clarify", %{tenant: tenant} do
    t = %{schema_name: tenant.schema_name, company_name: tenant.company_name, admin_email: nil}

    multi_args = %{
      classification: %{
        steps: [
          %{
            workflow: "contacts",
            action: "delete",
            params: %{"search_name" => "Marie"},
            routing_path: "deterministic"
          },
          %{
            workflow: "todos",
            action: "update",
            params: %{"subject" => "test"},
            routing_path: "deterministic"
          }
        ],
        prompt_tokens: 0,
        completion_tokens: 0,
        total_tokens: 0
      },
      tenant: t,
      channel: :http,
      user_id: "test-user",
      log: %{id: 0},
      text: "test"
    }

    {:ok, result} = DispatchModule.run(multi_args, %{}, [])
    assert result.action == "clarify"
    assert result.output =~ "séparément"
  end

  test "multi-step non-destructive executes both and combines output", %{tenant: tenant} do
    t = %{schema_name: tenant.schema_name, company_name: tenant.company_name, admin_email: nil}

    multi_args = %{
      classification: %{
        steps: [
          %{workflow: "contacts", action: "count", params: %{}, routing_path: "deterministic"},
          %{workflow: "help", action: "help", params: %{}, routing_path: "deterministic"}
        ],
        prompt_tokens: 0,
        completion_tokens: 0,
        total_tokens: 0
      },
      tenant: t,
      channel: :http,
      user_id: "test-user",
      log: %{id: 0},
      text: "test"
    }

    {:ok, result} = DispatchModule.run(multi_args, %{}, [])
    assert result.output =~ "2"
    assert result.output =~ "contacts"
  end

  test "contacts search by name routes to Contacts module", %{tenant: tenant} do
    {:ok, result} =
      DispatchModule.run(
        args("contacts", "search", %{"search_name" => "Marie"}, %{
          schema_name: tenant.schema_name,
          company_name: tenant.company_name,
          admin_email: tenant.admin_email
        }),
        %{},
        []
      )

    assert result.action == "search"
    assert result.output =~ "Marie"
  end

  test "fan-out above threshold stores pending and returns fanout pending", %{
    tenant: tenant,
    user_id: user_id
  } do
    alias CrmReactor.CRM.{Contact, ExecutionLog}
    alias CrmReactor.Repo

    schema = tenant.schema_name

    # Add 2 more contacts to go beyond threshold (already have 2, need >3)
    for name <- ["Carla Rossi", "Denis Leroy"] do
      %Contact{}
      |> Contact.changeset(%{
        first_name: String.split(name, " ") |> hd(),
        last_name: String.split(name, " ") |> List.last()
      })
      |> Repo.insert!(prefix: schema)
    end

    log =
      %ExecutionLog{}
      |> ExecutionLog.create_changeset(%{
        triggered_by: user_id,
        channel: "http",
        raw_input: "rappel pour tous"
      })
      |> Repo.insert!(prefix: schema)

    t = %{
      schema_name: schema,
      company_name: tenant.company_name,
      admin_email: nil
    }

    fanout_args = %{
      classification: %{
        steps: [
          %{
            id: "s",
            workflow: "contacts",
            action: "search",
            params: %{"search_name" => ""},
            routing_path: "deterministic",
            depends_on: [],
            for_each: nil,
            map_param: nil
          },
          %{
            id: "r",
            workflow: "todos",
            action: "create",
            params: %{"subject" => "Rappel"},
            routing_path: "deterministic",
            depends_on: ["s"],
            for_each: "$s.data.contacts",
            map_param: "contact_name"
          }
        ],
        prompt_tokens: 0,
        completion_tokens: 0,
        total_tokens: 0
      },
      tenant: t,
      channel: :http,
      user_id: user_id,
      log: log,
      text: "rappel pour tous"
    }

    {:ok, result} = DispatchModule.run(fanout_args, %{}, [])

    assert result.action == "pending"
    assert result.pending_type == "fanout"
    assert result.pending_id
  end
end
