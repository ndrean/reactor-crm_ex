defmodule CrmReactor.Reactors.Modules.DataExportTest do
  use CrmReactor.DataCase

  alias CrmReactor.CRM.ExecutionLog
  alias CrmReactor.Reactors.Modules.DataExport
  alias CrmReactor.Repo
  alias CrmReactor.TestFixtures

  setup do
    fixture = TestFixtures.provision_test_tenant()
    on_exit(fn -> TestFixtures.cleanup_tenant(fixture) end)

    log =
      %ExecutionLog{}
      |> ExecutionLog.create_changeset(%{
        triggered_by: fixture.user_id,
        channel: "http",
        raw_input: "exporte"
      })
      |> Repo.insert!(prefix: fixture.tenant.schema_name)

    %{fixture: fixture, log: log, schema: fixture.tenant.schema_name}
  end

  test "dump with nil admin_email creates export_email pending", %{
    fixture: fixture,
    log: log,
    schema: schema
  } do
    {:ok, result} =
      DataExport.execute(%{
        action: "dump",
        tenant_schema: schema,
        admin_email: nil,
        log_id: log.id,
        company_name: fixture.tenant.company_name
      })

    assert result.action == "pending"
    assert result.pending_type == "export_email"
    assert result.pending_id
  end

  test "dump with admin_email set sends export email", %{fixture: fixture, schema: schema} do
    {:ok, result} =
      DataExport.execute(%{
        action: "dump",
        tenant_schema: schema,
        admin_email: "admin@example.fr",
        log_id: nil,
        company_name: fixture.tenant.company_name
      })

    assert result.action == "dump"
    assert result.output =~ "admin@example.fr"
  end

  test "unsupported action returns error message" do
    {:ok, result} = DataExport.execute(%{action: "unknown"})
    assert result.output =~ "non supportée"
  end
end
