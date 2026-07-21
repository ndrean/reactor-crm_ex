defmodule CrmReactor.CacheListenerTest do
  use ExUnit.Case, async: false

  alias CrmReactor.CacheListener

  describe "handle_info/2" do
    setup do
      state = %{conn: nil}
      {:ok, state: state}
    end

    test "tenant_cache payload triggers TenantCache.reload_local", %{state: state} do
      msg = {:notification, nil, nil, "cache_reload", "tenant_cache"}
      assert {:noreply, ^state} = CacheListener.handle_info(msg, state)
    end

    test "subscription_cache payload triggers SubscriptionCache.reload_local", %{state: state} do
      msg = {:notification, nil, nil, "cache_reload", "subscription_cache"}
      assert {:noreply, ^state} = CacheListener.handle_info(msg, state)
    end

    test "unknown payload is ignored", %{state: state} do
      msg = {:notification, nil, nil, "cache_reload", "something_else"}
      assert {:noreply, ^state} = CacheListener.handle_info(msg, state)
    end

    test "unrelated message is ignored", %{state: state} do
      assert {:noreply, ^state} = CacheListener.handle_info(:random_msg, state)
    end
  end
end
