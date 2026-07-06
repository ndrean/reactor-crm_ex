defmodule CrmReactor.Reactors.Steps.FinalizeReplyTest do
  use CrmReactor.DataCase

  alias CrmReactor.CRM.ExecutionLog
  alias CrmReactor.Reactors.Steps.FinalizeReply
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
        raw_input: "test"
      })
      |> Repo.insert!(prefix: fixture.tenant.schema_name)

    tenant = %{
      schema_name: fixture.tenant.schema_name,
      company_name: fixture.tenant.company_name,
      admin_email: nil
    }

    %{log: log, tenant: tenant, schema: fixture.tenant.schema_name}
  end

  defp classification(workflow \\ "contacts", action \\ "search", tokens \\ {10, 5, 15}) do
    {pt, ct, tt} = tokens

    %{
      steps: [%{workflow: workflow, action: action, params: %{}, routing_path: "deterministic"}],
      prompt_tokens: pt,
      completion_tokens: ct,
      total_tokens: tt
    }
  end

  test "pending action skips DB update and returns result unchanged", %{
    log: log,
    tenant: tenant,
    schema: schema
  } do
    result = %{action: "pending", output: "Confirmez-vous ?", pending_id: "some-uuid"}

    assert {:ok, ^result} =
             FinalizeReply.run(
               %{
                 result: result,
                 log: log,
                 tenant: tenant,
                 classification: classification(),
                 attachment: nil
               },
               %{},
               []
             )

    # Log should still be in "processing" — not touched by FinalizeReply
    assert Repo.get!(ExecutionLog, log.id, prefix: schema).status == "processing"
  end

  test "completed action updates log to completed with output and token counts",
       %{log: log, tenant: tenant, schema: schema} do
    result = %{action: "search", output: "2 contacts trouvés"}

    assert {:ok, ^result} =
             FinalizeReply.run(
               %{
                 result: result,
                 log: log,
                 tenant: tenant,
                 classification: classification(),
                 attachment: nil
               },
               %{},
               []
             )

    updated = Repo.get!(ExecutionLog, log.id, prefix: schema)
    assert updated.status == "completed"
    assert updated.action == "search"
    assert updated.output == "2 contacts trouvés"
    assert updated.total_tokens == 15
    assert updated.prompt_tokens == 10
  end

  test "finalize returns the result map unchanged regardless of DB outcome",
       %{log: log, tenant: tenant} do
    result = %{action: "count", output: "Nombre de contacts : 2"}

    assert {:ok, ^result} =
             FinalizeReply.run(
               %{
                 result: result,
                 log: log,
                 tenant: tenant,
                 classification: classification("contacts", "count", {5, 3, 8}),
                 attachment: nil
               },
               %{},
               []
             )
  end

  test "with attachment saves execution_attachment record", %{
    log: log,
    tenant: tenant,
    schema: schema
  } do
    result = %{action: "create", output: "Contact créé"}

    attachment = %{
      filename: "contacts.vcf",
      content_type: "text/vcard",
      size_bytes: 250,
      storage_key: "tenant_test/uuid-contacts.vcf"
    }

    assert {:ok, ^result} =
             FinalizeReply.run(
               %{
                 result: result,
                 log: log,
                 tenant: tenant,
                 classification: classification("contacts", "create"),
                 attachment: attachment
               },
               %{},
               []
             )

    import Ecto.Query

    record =
      Repo.one!(
        from(a in CrmReactor.CRM.ExecutionAttachment, where: a.execution_log_id == ^log.id),
        prefix: schema
      )

    assert record.filename == "contacts.vcf"
    assert record.storage_key == "tenant_test/uuid-contacts.vcf"
    assert record.size_bytes == 250
  end
end
