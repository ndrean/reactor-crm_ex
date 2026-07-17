defmodule CrmReactor.Emails.GdprExportEmailTest do
  use CrmReactor.DataCase

  import Swoosh.TestAssertions

  alias CrmReactor.GDPR.DataSubject
  alias CrmReactor.Tenants.Provisioner

  setup :set_swoosh_global

  setup do
    tid = "gdpr_email_#{System.unique_integer([:positive])}"
    email = "subject@gdprcorp.fr"
    telegram_id = "7777777777"

    {:ok, tenant} =
      Provisioner.provision(tid, "GDPR Corp", telegram_id, email: email, telegram_id: telegram_id)

    on_exit(fn -> Provisioner.drop_tenant(tenant) end)
    %{tenant: tenant, email: email, telegram_id: telegram_id}
  end

  test "export_and_email/1 sends personal data to email via telegram_id lookup", %{
    telegram_id: tg_id,
    email: email
  } do
    {:ok, result} = DataSubject.export_and_email(tg_id)

    assert result.email_sent == true
    assert result.user_identifier == tg_id

    assert_email_sent(fn em ->
      assert em.subject == "Vos données personnelles CRM – GDPR Corp"
      assert em.to == [{"", email}]
      assert length(em.attachments) == 1
      [att] = em.attachments
      assert att.filename =~ "donnees_personnelles"
      assert att.content_type == "application/json"
    end)
  end

  test "export_and_email/1 sends data via email lookup", %{email: email} do
    {:ok, result} = DataSubject.export_and_email(email)

    assert result.email_sent == true
    assert result.user_identifier == email
  end

  test "export_and_email/1 returns error for unknown user" do
    assert {:error, :not_found} = DataSubject.export_and_email("0000000000")
  end
end
