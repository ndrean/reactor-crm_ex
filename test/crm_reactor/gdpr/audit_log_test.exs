defmodule CrmReactor.GDPR.AuditLogTest do
  use CrmReactor.DataCase

  alias CrmReactor.GDPR.AuditLog
  alias CrmReactor.Repo

  import Ecto.Query

  setup do
    on_exit(fn ->
      Repo.delete_all(AuditLog)
    end)
  end

  describe "record/4" do
    test "inserts an audit log entry" do
      assert {:ok, log} = AuditLog.record("export", "user@test.fr", "admin_api")

      assert log.action == "export"
      assert log.subject_id == "user@test.fr"
      assert log.performed_by == "admin_api"
      assert log.details == nil

      # performed_at is DB-default; verify it was persisted
      reloaded = Repo.get!(AuditLog, log.id)
      assert %DateTime{} = reloaded.performed_at
    end

    test "inserts with details" do
      details = %{schema: "customer_test", contact_id: 42}
      assert {:ok, _log} = AuditLog.record("erase_contact", "42", "admin_api", details)

      reloaded = Repo.one!(from(a in AuditLog, where: a.subject_id == "42"))
      assert reloaded.details == %{"schema" => "customer_test", "contact_id" => 42}
    end

    test "validates action inclusion" do
      assert {:error, changeset} = AuditLog.record("invalid_action", "user", "admin")
      assert %{action: _} = errors_on(changeset)
    end

    test "all four actions are accepted" do
      for action <- ~w(export email_export erase erase_contact) do
        assert {:ok, _} = AuditLog.record(action, "user_#{action}", "admin_api")
      end

      count = Repo.aggregate(from(a in AuditLog), :count)
      assert count == 4
    end
  end
end
