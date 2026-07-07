defmodule CrmReactor.AI.SubscriptionCacheTest do
  use CrmReactor.DataCase, async: false

  alias CrmReactor.AI.SubscriptionCache

  describe "enabled?/2 defaults" do
    test "unknown tenant returns true" do
      assert SubscriptionCache.enabled?("no-such-tenant", "contacts") == true
    end

    test "unknown workflow for known tenant returns true" do
      assert SubscriptionCache.enabled?("any-tenant", "nonexistent-workflow") == true
    end

    test "nil tenant_id returns true (default-true for unresolved tenants)" do
      assert SubscriptionCache.enabled?(nil, "contacts") == true
    end
  end

  describe "set/3 and enabled?/2" do
    test "disabling a workflow makes enabled? return false" do
      :ok = SubscriptionCache.set("sub-test-tenant", "contacts", false)
      assert SubscriptionCache.enabled?("sub-test-tenant", "contacts") == false
    end

    test "re-enabling returns true" do
      :ok = SubscriptionCache.set("sub-test-tenant-2", "todos", false)
      assert SubscriptionCache.enabled?("sub-test-tenant-2", "todos") == false

      :ok = SubscriptionCache.set("sub-test-tenant-2", "todos", true)
      assert SubscriptionCache.enabled?("sub-test-tenant-2", "todos") == true
    end

    test "disabling one workflow does not affect another" do
      :ok = SubscriptionCache.set("sub-test-tenant-3", "data", false)
      assert SubscriptionCache.enabled?("sub-test-tenant-3", "data") == false
      assert SubscriptionCache.enabled?("sub-test-tenant-3", "contacts") == true
    end

    test "set persists to DB (survives ETS rebuild)" do
      :ok = SubscriptionCache.set("sub-test-tenant-4", "contacts", false)

      # Reload the GenServer state from DB to verify persistence
      GenServer.cast(SubscriptionCache, :reload)
      # Give the async cast time to complete
      :timer.sleep(50)

      assert SubscriptionCache.enabled?("sub-test-tenant-4", "contacts") == false
    end
  end
end
