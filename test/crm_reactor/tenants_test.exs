defmodule CrmReactor.TenantsTest do
  use CrmReactor.DataCase

  alias CrmReactor.Tenants
  alias CrmReactor.TestFixtures

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
    CrmReactor.Repo.query!(
      "UPDATE global_registry.tenants SET is_active = false WHERE schema_name = $1",
      [tenant.schema_name]
    )

    assert {:error, :unknown_user} = Tenants.schema_for_user(user_id)
  end
end
