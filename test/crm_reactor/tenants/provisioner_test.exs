defmodule CrmReactor.Tenants.ProvisionerTest do
  use CrmReactor.DataCase

  alias CrmReactor.Tenants.Provisioner

  test "provision creates schema and tenant record" do
    tid = "prov_test_#{System.unique_integer([:positive])}"

    uniq = System.unique_integer([:positive])

    {:ok, tenant} =
      Provisioner.provision(tid, "Prov Corp", nil,
        email: "prov_#{uniq}@test.com",
        telegram_id: "123#{uniq}"
      )

    assert tenant.tenant_id == tid
    assert tenant.schema_name == "customer_#{tid}"
    assert tenant.is_active == true

    {:ok, result} =
      Repo.query(
        "SELECT table_name FROM information_schema.tables WHERE table_schema = $1 ORDER BY table_name",
        [tenant.schema_name]
      )

    tables = List.flatten(result.rows)
    assert "contacts" in tables
    assert "todos" in tables
    assert "execution_logs" in tables

    on_exit(fn -> Provisioner.drop_tenant(tenant) end)
  end

  test "toggle_active flips tenant status" do
    tid = "toggle_#{System.unique_integer([:positive])}"
    {:ok, tenant} = Provisioner.provision(tid, "Toggle Corp")

    {:ok, updated} = Provisioner.toggle_active(tid, false)
    assert updated.is_active == false

    {:ok, updated} = Provisioner.toggle_active(tid, true)
    assert updated.is_active == true

    on_exit(fn -> Provisioner.drop_tenant(tenant) end)
  end

  test "toggle_active returns error for unknown tenant" do
    assert {:error, :not_found} = Provisioner.toggle_active("nonexistent", false)
  end
end
