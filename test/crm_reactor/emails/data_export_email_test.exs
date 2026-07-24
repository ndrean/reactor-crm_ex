defmodule CrmReactor.Emails.DataExportEmailTest do
  use CrmReactor.DataCase
  use Oban.Testing, repo: CrmReactor.Repo

  import Swoosh.TestAssertions

  alias CrmReactor.Reactors.Modules.Mutations
  alias CrmReactor.Tenants.Provisioner

  setup :set_swoosh_global

  setup do
    tid = "email_export_#{System.unique_integer([:positive])}"
    user_id = "5555555555"

    {:ok, tenant} =
      Provisioner.provision(tid, "Test Corp", user_id,
        admin_email: "admin@testcorp.fr",
        email: "user@testcorp.fr",
        telegram_id: user_id
      )

    on_exit(fn -> Provisioner.drop_tenant(tenant) end)

    tenant_map = %{
      tenant_id: tenant.tenant_id,
      schema_name: tenant.schema_name,
      company_name: tenant.company_name,
      admin_email: tenant.admin_email,
      webhook_url: tenant.webhook_url,
      webhook_secret: tenant.webhook_secret
    }

    %{tenant: tenant, user_id: user_id, tenant_map: tenant_map}
  end

  test "data export sends email to admin_email when configured", %{
    user_id: user_id,
    tenant_map: tenant_map
  } do
    {:ok, result} =
      Reactor.run(CrmReactor.Reactors.MasterIngest, %{
        user_id: user_id,
        raw_input: "exporte les données",
        is_audio: false,
        channel: :http,
        job_id: "http-#{Ecto.UUID.generate()}",
        attachment: nil,
        tenant: tenant_map
      })

    assert result.action == "dump"
    assert result.output =~ "admin@testcorp.fr"

    assert_email_sent(fn email ->
      assert email.subject == "Votre export de données CRM – Test Corp"
      assert email.to == [{"", "admin@testcorp.fr"}]
    end)
  end

  test "data export without admin_email returns pending and asks for email" do
    tid = "no_email_#{System.unique_integer([:positive])}"
    user_id = "6666666666"

    {:ok, tenant} =
      Provisioner.provision(tid, "No Email Corp", user_id,
        email: "noemail@test.com",
        telegram_id: user_id
      )

    on_exit(fn -> Provisioner.drop_tenant(tenant) end)

    {:ok, result} =
      Reactor.run(CrmReactor.Reactors.MasterIngest, %{
        user_id: user_id,
        raw_input: "exporte les données",
        is_audio: false,
        channel: :http,
        job_id: "http-#{Ecto.UUID.generate()}",
        attachment: nil,
        tenant: build_tenant_map(tenant)
      })

    assert result.action == "pending"
    assert byte_size(result.pending_id) > 0
    assert result.output =~ "email"
    assert_no_email_sent()
  end

  test "data export pending loop: providing email triggers export and sends it" do
    tid = "loop_#{System.unique_integer([:positive])}"
    user_id = "7777777777"

    {:ok, tenant} =
      Provisioner.provision(tid, "Loop Corp", user_id,
        email: "loop@test.com",
        telegram_id: user_id
      )

    on_exit(fn -> Provisioner.drop_tenant(tenant) end)

    # Step 1: export requested — no email on record → pending
    {:ok, pending} =
      Reactor.run(CrmReactor.Reactors.MasterIngest, %{
        user_id: user_id,
        raw_input: "exporte mes données",
        is_audio: false,
        channel: :http,
        job_id: "http-#{Ecto.UUID.generate()}",
        attachment: nil,
        tenant: build_tenant_map(tenant)
      })

    assert pending.action == "pending"
    assert byte_size(pending.pending_id) > 0
    assert_no_email_sent()

    # Step 2: user provides email via confirm
    {:ok, result} =
      Mutations.confirm_system(pending.pending_id, "admin@loopcorp.fr", tenant.schema_name)

    assert result.action == "dump"
    assert result.output =~ "admin@loopcorp.fr"

    assert_email_sent(fn email ->
      assert email.subject == "Votre export de données CRM – Loop Corp"
      assert email.to == [{"", "admin@loopcorp.fr"}]
    end)
  end

  test "data export confirm with invalid email returns error" do
    tid = "bad_email_#{System.unique_integer([:positive])}"
    user_id = "8888888888"

    {:ok, tenant} =
      Provisioner.provision(tid, "Bad Email Corp", user_id,
        email: "bad@test.com",
        telegram_id: user_id
      )

    on_exit(fn -> Provisioner.drop_tenant(tenant) end)

    {:ok, pending} =
      Reactor.run(CrmReactor.Reactors.MasterIngest, %{
        user_id: user_id,
        raw_input: "exporte mes données",
        is_audio: false,
        channel: :http,
        job_id: "http-#{Ecto.UUID.generate()}",
        attachment: nil,
        tenant: build_tenant_map(tenant)
      })

    assert {:error, :invalid_email} =
             Mutations.confirm_system(pending.pending_id, "not-an-email", tenant.schema_name)

    assert_no_email_sent()
  end

  test "providing email for export does NOT persist it to tenant record" do
    tid = "no_persist_#{System.unique_integer([:positive])}"
    user_id = "9999999999"

    {:ok, tenant} =
      Provisioner.provision(tid, "NoPersist Corp", user_id,
        email: "nopersist@test.com",
        telegram_id: user_id
      )

    on_exit(fn -> Provisioner.drop_tenant(tenant) end)

    {:ok, pending} =
      Reactor.run(CrmReactor.Reactors.MasterIngest, %{
        user_id: user_id,
        raw_input: "exporte mes données",
        is_audio: false,
        channel: :http,
        job_id: "http-#{Ecto.UUID.generate()}",
        attachment: nil,
        tenant: build_tenant_map(tenant)
      })

    {:ok, _result} =
      Mutations.confirm_system(pending.pending_id, "temp@example.fr", tenant.schema_name)

    # Verify the email was NOT saved to the tenant record
    reloaded = Repo.get_by!(CrmReactor.Tenants.Tenant, tenant_id: tenant.tenant_id)
    assert reloaded.admin_email == nil
  end

  defp build_tenant_map(tenant) do
    %{
      tenant_id: tenant.tenant_id,
      schema_name: tenant.schema_name,
      company_name: tenant.company_name,
      admin_email: tenant.admin_email,
      webhook_url: tenant.webhook_url,
      webhook_secret: tenant.webhook_secret
    }
  end
end
