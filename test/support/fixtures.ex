defmodule CrmReactor.TestFixtures do
  @moduledoc "Test helpers for provisioning tenants and seeding data."

  alias CrmReactor.CRM.Contact
  alias CrmReactor.Repo
  alias CrmReactor.Tenants.Provisioner

  def provision_test_tenant(suffix \\ nil) do
    tid = "test_#{suffix || System.unique_integer([:positive])}"
    email = "test_#{tid}@example.com"
    telegram_id = "5555555555"

    {:ok, tenant} =
      Provisioner.provision(tid, "Test Corp", nil, email: email, telegram_id: telegram_id)

    for {first, last, em, phone} <- [
          {"Marie", "Dupont", "marie@test.fr", "0601020304"},
          {"Paul", "Martin", "paul@test.fr", "0605060708"}
        ] do
      %Contact{}
      |> Contact.changeset(%{
        first_name: first,
        last_name: last,
        email: em,
        phone: phone
      })
      |> Repo.insert!(prefix: tenant.schema_name)
    end

    tomorrow = Date.add(Date.utc_today(), 1)
    next_week = Date.add(Date.utc_today(), 7)

    Repo.query!(
      "INSERT INTO #{tenant.schema_name}.todos (subject, due_date, created_by) VALUES ($1, $2, $3), ($4, $5, $6)",
      ["Appeler fournisseur", tomorrow, email, "Envoyer devis", next_week, email]
    )

    # Appointment (todo with starts_at)
    tomorrow_2pm =
      DateTime.new!(tomorrow, ~T[14:00:00], "Etc/UTC")

    Repo.query!(
      "INSERT INTO #{tenant.schema_name}.todos (subject, created_by, starts_at, ends_at, location, reminder_minutes) VALUES ($1, $2, $3, $4, $5, $6)",
      ["Réunion client", email, tomorrow_2pm, DateTime.add(tomorrow_2pm, 3600), "Bureau", 30]
    )

    # Seed expense
    Repo.query!(
      "INSERT INTO #{tenant.schema_name}.expenses (amount, expense_date, category, description, created_by) VALUES ($1, $2, $3, $4, $5)",
      [Decimal.new("42.50"), Date.utc_today(), "restaurant", "Déjeuner équipe", email]
    )

    %{tenant: tenant, user_id: email, telegram_id: telegram_id}
  end

  def tenant_map(%{tenant: tenant}) do
    %{
      tenant_id: tenant.tenant_id,
      schema_name: tenant.schema_name,
      company_name: tenant.company_name,
      admin_email: tenant.admin_email,
      webhook_url: tenant.webhook_url,
      webhook_secret: tenant.webhook_secret,
      status: "active"
    }
  end

  def cleanup_tenant(%{tenant: tenant}) do
    Provisioner.drop_tenant(tenant)
  end
end
