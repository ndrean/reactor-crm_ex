defmodule CrmReactor.TenantsTest do
  use CrmReactor.DataCase

  alias CrmReactor.{Tenants, TestFixtures}
  alias CrmReactor.Tenants.Provisioner

  setup do
    fixture = TestFixtures.provision_test_tenant()
    on_exit(fn -> TestFixtures.cleanup_tenant(fixture) end)
    fixture
  end

  test "known active user returns {:ok, schema_name}", %{tenant: tenant, user_id: user_id} do
    assert {:ok, schema} = Tenants.schema_for_user(user_id)
    assert schema == tenant.schema_name
  end

  test "unknown user returns {:error, :unknown_user}" do
    assert {:error, :unknown_user} =
             Tenants.schema_for_user("no_such_user_#{System.unique_integer([:positive])}")
  end

  test "inactive tenant returns {:error, :unknown_user}", %{tenant: tenant, user_id: user_id} do
    {:ok, _} = Provisioner.toggle_active(tenant.tenant_id, false)

    assert {:error, :unknown_user} = Tenants.schema_for_user(user_id)
  end
end
