defmodule CrmReactor.AI.InputGuardTest do
  use ExUnit.Case, async: true

  alias CrmReactor.AI.InputGuard

  describe "validate/1" do
    test "allows normal text" do
      assert :ok = InputGuard.validate("cherche Marie Dupont")
    end

    test "rejects DROP TABLE" do
      assert {:rejected, _} = InputGuard.validate("DROP TABLE contacts")
    end

    test "rejects UPDATE SET" do
      assert {:rejected, _} = InputGuard.validate("UPDATE contacts SET name = 'x'")
    end

    test "rejects UNION SELECT" do
      assert {:rejected, _} = InputGuard.validate("' UNION SELECT * FROM users --")
    end

    test "rejects input exceeding byte limit" do
      oversized = String.duplicate("a", 4_097)
      assert {:rejected, _} = InputGuard.validate(oversized)
    end

    test "allows input at exactly the byte limit" do
      exactly = String.duplicate("a", 4_096)
      assert :ok = InputGuard.validate(exactly)
    end
  end
end
