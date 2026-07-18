defmodule CrmReactor.Reactors.Modules.MutationsIsolationTest do
  @moduledoc "Tests that pending mutations are tenant-isolated."
  use CrmReactor.DataCase

  alias CrmReactor.CRM.ExecutionLog
  alias CrmReactor.Reactors.Modules.Mutations
  alias CrmReactor.{Repo, TestFixtures}
  alias CrmReactor.Tenants.Provisioner

  setup do
    # Provision two separate tenants with different users
    # provision_test_tenant/1 hardcodes user_id "5555555555", so we provision
    # tenant B manually with a different user_id to avoid the unique constraint.
    fixture_a = TestFixtures.provision_test_tenant("iso_a")

    user_b = "user_b@test.com"

    {:ok, tenant_b} =
      Provisioner.provision("test_iso_b", "Test Corp B", user_b)

    on_exit(fn ->
      TestFixtures.cleanup_tenant(fixture_a)
      TestFixtures.cleanup_tenant(%{tenant: tenant_b})
    end)

    %{
      tenant_a: fixture_a.tenant,
      user_a: fixture_a.user_id,
      tenant_b: tenant_b,
      user_b: user_b
    }
  end

  defp insert_pending_log(schema, user_id) do
    pending_id = Ecto.UUID.generate()

    %ExecutionLog{}
    |> ExecutionLog.create_changeset(%{
      triggered_by: user_id,
      channel: "test",
      raw_input: "supprime un contact",
      job_id: "test-#{pending_id}"
    })
    |> Ecto.Changeset.put_change(:status, "pending")
    |> Ecto.Changeset.put_change(:pending_id, pending_id)
    |> Ecto.Changeset.put_change(:action, "delete")
    |> Ecto.Changeset.put_change(:module, "contacts")
    |> Ecto.Changeset.put_change(:proposed_params, %{"contact_id" => 999})
    |> Repo.insert!(prefix: schema)

    pending_id
  end

  test "user cannot confirm a pending action from another tenant", ctx do
    pending_id = insert_pending_log(ctx.tenant_a.schema_name, ctx.user_a)

    # User B tries to confirm User A's pending action → not found (scoped search)
    assert {:error, :pending_not_found} =
             Mutations.confirm(pending_id, "confirm", ctx.user_b)
  end

  test "user cannot reject a pending action from another tenant", ctx do
    pending_id = insert_pending_log(ctx.tenant_a.schema_name, ctx.user_a)

    assert {:error, :pending_not_found} =
             Mutations.confirm(pending_id, "reject", ctx.user_b)
  end

  test "user can confirm their own pending action", ctx do
    pending_id = insert_pending_log(ctx.tenant_a.schema_name, ctx.user_a)

    # contact_id 999 doesn't exist, but Ecto.NoResultsError proves
    # we reached the mutation dispatch (past isolation check)
    assert_raise Ecto.NoResultsError, fn ->
      Mutations.confirm(pending_id, "confirm", ctx.user_a)
    end
  end

  test "different user in same tenant gets :unauthorized", ctx do
    # Create a second user mapping in tenant A
    alias CrmReactor.Tenants.UserMapping

    other_user_id = "9999999999"

    %UserMapping{}
    |> UserMapping.changeset(%{
      tenant_id: ctx.tenant_a.tenant_id,
      email: "other_#{other_user_id}@test.com",
      telegram_id: other_user_id
    })
    |> Repo.insert!()

    pending_id = insert_pending_log(ctx.tenant_a.schema_name, ctx.user_a)

    # Same tenant, different user → unauthorized
    assert {:error, :unauthorized} =
             Mutations.confirm(pending_id, "confirm", other_user_id)
  end
end
