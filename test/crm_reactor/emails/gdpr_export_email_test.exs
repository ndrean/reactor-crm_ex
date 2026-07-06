defmodule CrmReactor.Emails.GdprExportEmailTest do
  use CrmReactor.DataCase

  import Swoosh.TestAssertions

  alias CrmReactor.GDPR.DataSubject
  alias CrmReactor.Tenants.Provisioner

  setup :set_swoosh_global

  setup do
    tid = "gdpr_email_#{System.unique_integer([:positive])}"
    user_id = "7777777777"

    {:ok, tenant} =
      Provisioner.provision(tid, "GDPR Corp", user_id, user_email: "subject@gdprcorp.fr")

    on_exit(fn -> Provisioner.drop_tenant(tenant) end)
    %{tenant: tenant, user_id: user_id}
  end

  test "export_and_email/1 sends personal data to user_email", %{user_id: user_id} do
    {:ok, result} = DataSubject.export_and_email(user_id)

    assert result.email_sent == true
    assert result.user_identifier == user_id

    assert_email_sent(fn email ->
      assert email.subject == "Vos données personnelles CRM – GDPR Corp"
      assert email.to == [{"", "subject@gdprcorp.fr"}]
      assert length(email.attachments) == 1
      [att] = email.attachments
      assert att.filename =~ "donnees_personnelles"
      assert att.content_type == "application/json"
    end)
  end

  test "export_and_email/1 returns email_sent: false when no user_email registered" do
    tid = "gdpr_noemail_#{System.unique_integer([:positive])}"
    user_id = "8888888888"
    {:ok, tenant} = Provisioner.provision(tid, "No Email Corp", user_id)
    on_exit(fn -> Provisioner.drop_tenant(tenant) end)

    {:ok, result} = DataSubject.export_and_email(user_id)

    assert result.email_sent == false
    assert result.user_identifier == user_id
    assert_no_email_sent()
  end

  test "export_and_email/1 returns error for unknown user" do
    assert {:error, :not_found} = DataSubject.export_and_email("0000000000")
  end
end
