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
        user_email: "user@testcorp.fr"
      )

    on_exit(fn -> Provisioner.drop_tenant(tenant) end)
    %{tenant: tenant, user_id: user_id}
  end

  test "data export sends email to admin_email when configured", %{user_id: user_id} do
    {:ok, result} =
      Reactor.run(CrmReactor.Reactors.MasterIngest, %{
        user_id: user_id,
        raw_input: "exporte les données",
        is_audio: false,
        channel: :http,
        job_id: "http-#{Ecto.UUID.generate()}",
        attachment: nil,
        tenant_override: nil
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
    {:ok, tenant} = Provisioner.provision(tid, "No Email Corp", user_id)
    on_exit(fn -> Provisioner.drop_tenant(tenant) end)

    {:ok, result} =
      Reactor.run(CrmReactor.Reactors.MasterIngest, %{
        user_id: user_id,
        raw_input: "exporte les données",
        is_audio: false,
        channel: :http,
        job_id: "http-#{Ecto.UUID.generate()}",
        attachment: nil,
        tenant_override: nil
      })

    assert result.action == "pending"
    assert result.pending_id != nil
    assert result.output =~ "email"
    assert_no_email_sent()
  end

  test "data export pending loop: providing email triggers export and sends it" do
    tid = "loop_#{System.unique_integer([:positive])}"
    user_id = "7777777777"
    {:ok, tenant} = Provisioner.provision(tid, "Loop Corp", user_id)
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
        tenant_override: nil
      })

    assert pending.action == "pending"
    assert pending.pending_id != nil
    assert_no_email_sent()

    # Step 2: user provides email via confirm
    {:ok, result} = Mutations.confirm(pending.pending_id, "admin@loopcorp.fr")
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
    {:ok, tenant} = Provisioner.provision(tid, "Bad Email Corp", user_id)
    on_exit(fn -> Provisioner.drop_tenant(tenant) end)

    {:ok, pending} =
      Reactor.run(CrmReactor.Reactors.MasterIngest, %{
        user_id: user_id,
        raw_input: "exporte mes données",
        is_audio: false,
        channel: :http,
        job_id: "http-#{Ecto.UUID.generate()}",
        attachment: nil,
        tenant_override: nil
      })

    assert {:error, :invalid_email} = Mutations.confirm(pending.pending_id, "not-an-email")
    assert_no_email_sent()
  end
end
