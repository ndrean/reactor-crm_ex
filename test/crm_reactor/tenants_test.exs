defmodule CrmReactor.TenantsTest do
  use CrmReactor.DataCase

  alias CrmReactor.Tenants
  alias CrmReactor.Tenants.{Provisioner, TenantCache}
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
    {:ok, _} = Provisioner.toggle_active(tenant.tenant_id, false)

    assert {:error, :unknown_user} = Tenants.schema_for_user(user_id)
  end

  describe "resolve_canonical_id/1" do
    test "email resolves to itself", %{user_id: email} do
      assert TenantCache.resolve_canonical_id(email) == email
    end

    test "telegram_id resolves to canonical email", %{user_id: email, telegram_id: tg_id} do
      assert TenantCache.resolve_canonical_id(tg_id) == email
    end

    test "unknown identifier returns itself" do
      unknown = "unknown_#{System.unique_integer([:positive])}"
      assert TenantCache.resolve_canonical_id(unknown) == unknown
    end
  end
end
