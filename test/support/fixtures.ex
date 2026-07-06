defmodule CrmReactor.TestFixtures do
  @moduledoc "Test helpers for provisioning tenants and seeding data."

  alias CrmReactor.CRM.Contact
  alias CrmReactor.Repo
  alias CrmReactor.Tenants.Provisioner

  def provision_test_tenant(suffix \\ nil) do
    tid = "test_#{suffix || System.unique_integer([:positive])}"
    user_id = "5555555555"
    {:ok, tenant} = Provisioner.provision(tid, "Test Corp", user_id)

    for {first, last, email, phone} <- [
          {"Marie", "Dupont", "marie@test.fr", "0601020304"},
          {"Paul", "Martin", "paul@test.fr", "0605060708"}
        ] do
      %Contact{}
      |> Contact.changeset(%{
        first_name: first,
        last_name: last,
        email: email,
        phone: phone
      })
      |> Repo.insert!(prefix: tenant.schema_name)
    end

    tomorrow = Date.add(Date.utc_today(), 1)
    next_week = Date.add(Date.utc_today(), 7)

    Repo.query!(
      "INSERT INTO #{tenant.schema_name}.todos (subject, due_date, created_by) VALUES ($1, $2, $3), ($4, $5, $6)",
      ["Appeler fournisseur", tomorrow, user_id, "Envoyer devis", next_week, user_id]
    )

    %{tenant: tenant, user_id: user_id}
  end

  def cleanup_tenant(%{tenant: tenant}) do
    Provisioner.drop_tenant(tenant)
  end
end
