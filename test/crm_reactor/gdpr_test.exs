defmodule CrmReactor.GDPRTest do
  @moduledoc "Tests for GDPR data subject rights: export, erasure, retention."
  use CrmReactor.DataCase

  alias CrmReactor.CRM.{Contact, ExecutionLog}
  alias CrmReactor.GDPR.DataSubject
  alias CrmReactor.Tenants.UserMapping
  alias CrmReactor.TestFixtures

  import Ecto.Query

  setup do
    fixture = TestFixtures.provision_test_tenant()
    on_exit(fn -> TestFixtures.cleanup_tenant(fixture) end)
    Map.put(fixture, :tenant_map, TestFixtures.tenant_map(fixture))
  end

  describe "export/1" do
    test "returns all data for a user", %{user_id: uid, tenant: tenant} do
      {:ok, data} = DataSubject.export(uid)

      assert data.user_identifier == uid
      assert data.tenant.tenant_id == tenant.tenant_id
      assert length(data.contacts) == 2
      assert data.exported_at
    end

    test "returns error for unknown user" do
      assert {:error, :not_found} = DataSubject.export("unknown")
    end
  end

  describe "erase/1" do
    test "redacts execution logs and removes user mapping", %{
      user_id: uid,
      tenant: tenant,
      tenant_map: tenant_map
    } do
      Reactor.run(CrmReactor.Reactors.MasterIngest, %{
        user_id: uid,
        raw_input: "cherche Marie",
        is_audio: false,
        channel: :http,
        job_id: nil,
        attachment: nil,
        tenant: tenant_map
      })

      {:ok, _} = DataSubject.erase(uid)

      logs = Repo.all(ExecutionLog, prefix: tenant.schema_name)
      assert Enum.all?(logs, &(&1.status == "erased"))
      assert Enum.all?(logs, &(&1.raw_input == "[REDACTED]"))

      assert Repo.all(from(m in UserMapping, where: m.email == ^uid)) == []
    end

    test "returns error for unknown user" do
      assert {:error, :not_found} = DataSubject.erase("unknown")
    end
  end

  describe "erase_contact/2" do
    test "deletes contact and redacts matching logs", %{
      user_id: uid,
      tenant: tenant,
      tenant_map: tenant_map
    } do
      Reactor.run(CrmReactor.Reactors.MasterIngest, %{
        user_id: uid,
        raw_input: "cherche Marie",
        is_audio: false,
        channel: :http,
        job_id: nil,
        attachment: nil,
        tenant: tenant_map
      })

      [marie | _] =
        Repo.all(from(c in Contact, where: c.first_name == "Marie"), prefix: tenant.schema_name)

      {:ok, _} = DataSubject.erase_contact(tenant.schema_name, marie.id)

      assert Repo.get(Contact, marie.id, prefix: tenant.schema_name) == nil

      logs =
        Repo.all(from(l in ExecutionLog, where: l.raw_input == "[REDACTED]"),
          prefix: tenant.schema_name
        )

      assert logs != []
    end
  end

  describe "export_and_email/1" do
    test "with email returns email_sent: true", %{user_id: uid} do
      {:ok, data} = DataSubject.export_and_email(uid)
      assert data.email_sent == true
      assert data.user_identifier == uid
    end

    test "returns error for unknown user" do
      assert {:error, :not_found} = DataSubject.export_and_email("no_such_user_99999")
    end
  end

  describe "erase_contact/2 error path" do
    test "returns error for non-existent contact", %{tenant: tenant} do
      assert {:error, :not_found} = DataSubject.erase_contact(tenant.schema_name, 999_999_999)
    end
  end

  describe "encrypted fields" do
    test "email and phone are stored encrypted", %{tenant: tenant} do
      [contact | _] = Repo.all(Contact, prefix: tenant.schema_name)

      assert contact.email == "marie@test.fr"
      assert contact.phone == "0601020304"

      raw =
        Repo.query!(
          "SELECT email FROM #{tenant.schema_name}.contacts WHERE id = $1",
          [contact.id]
        )

      [[raw_email]] = raw.rows
      refute raw_email == "marie@test.fr"
      assert is_binary(raw_email)
    end
  end
end
