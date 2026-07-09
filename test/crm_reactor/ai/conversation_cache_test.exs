defmodule CrmReactor.AI.ConversationCacheTest do
  use ExUnit.Case, async: true

  alias CrmReactor.AI.ConversationCache

  setup do
    # Use unique user_id per test to avoid cross-test interference
    %{user_id: "user_#{System.unique_integer([:positive])}"}
  end

  test "put/get round-trip", %{user_id: uid} do
    ConversationCache.put(uid, "cherche Marie", "Voici Marie Dupont")
    context = ConversationCache.get(uid)

    assert context == [{:user, "cherche Marie"}, {:assistant, "Voici Marie Dupont"}]
  end

  test "returns empty list for unknown user" do
    assert ConversationCache.get("unknown_#{System.unique_integer([:positive])}") == []
  end

  test "max 3 pairs overflow evicts oldest", %{user_id: uid} do
    ConversationCache.put(uid, "msg1", "reply1")
    ConversationCache.put(uid, "msg2", "reply2")
    ConversationCache.put(uid, "msg3", "reply3")
    ConversationCache.put(uid, "msg4", "reply4")

    context = ConversationCache.get(uid)
    assert length(context) == 6
    # Oldest pair (msg1/reply1) should be evicted
    refute Enum.any?(context, fn {_, text} -> text == "msg1" end)
    assert Enum.any?(context, fn {_, text} -> text == "msg2" end)
    assert Enum.any?(context, fn {_, text} -> text == "msg4" end)
  end

  test "multiple pairs accumulate correctly", %{user_id: uid} do
    ConversationCache.put(uid, "a", "b")
    ConversationCache.put(uid, "c", "d")

    context = ConversationCache.get(uid)

    assert context == [
             {:user, "a"},
             {:assistant, "b"},
             {:user, "c"},
             {:assistant, "d"}
           ]
  end
end
