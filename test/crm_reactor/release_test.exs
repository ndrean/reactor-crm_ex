defmodule CrmReactor.ReleaseTest do
  use CrmReactor.DataCase

  alias CrmReactor.Accounts.{Account, AccountToken}
  alias CrmReactor.Release
  alias CrmReactor.Repo

  @valid_password "password1234"

  defp create_admin(email \\ "admin_#{System.unique_integer([:positive])}@test.com") do
    {:ok, account} =
      %Account{}
      |> Account.registration_changeset(%{email: email, password: @valid_password, role: "admin"})
      |> Repo.insert()

    account
  end

  # ── Tests that require exact account counts (isolated) ──────────────

  @tag :bootstrap_isolation
  test "list_admins/0 prints message when no admins, lists when one exists" do
    Repo.delete_all(AccountToken)
    Repo.delete_all(Account)

    output = capture_io(fn -> Release.list_admins() end)
    assert output =~ "No admin accounts found."

    admin = create_admin("listtest@example.com")
    output = capture_io(fn -> Release.list_admins() end)
    assert output =~ admin.email
    assert output =~ "Total: 1"
  end

  @tag :bootstrap_isolation
  test "delete_admin/1 refuses to delete the last admin" do
    Repo.delete_all(AccountToken)
    Repo.delete_all(Account)
    create_admin("sole@example.com")

    output = capture_io(fn -> Release.delete_admin("sole@example.com") end)
    assert output =~ "Cannot delete the last admin"
    assert Repo.get_by(Account, email: "sole@example.com")
  end

  # ── Tests that work with unique emails (safe in shared sandbox) ─────

  describe "delete_admin/1" do
    test "deletes an admin and revokes tokens" do
      admin1 = create_admin("del1_#{System.unique_integer([:positive])}@example.com")
      _admin2 = create_admin("del2_#{System.unique_integer([:positive])}@example.com")

      {token, token_struct} = AccountToken.build_session_token(admin1)
      Repo.insert!(token_struct)
      assert Repo.get_by(AccountToken, token: token)

      output = capture_io(fn -> Release.delete_admin(admin1.email) end)
      assert output =~ "Deleted admin account"
      refute Repo.get_by(Account, email: admin1.email)
      refute Repo.get_by(AccountToken, token: token)
    end

    test "prints error for non-existent admin" do
      output = capture_io(fn -> Release.delete_admin("nobody@example.com") end)
      assert output =~ "No admin account found"
    end
  end

  describe "reset_password/2" do
    test "resets password and revokes session tokens" do
      admin = create_admin("reset_#{System.unique_integer([:positive])}@example.com")

      {_token, token_struct} = AccountToken.build_session_token(admin)
      Repo.insert!(token_struct)

      output = capture_io(fn -> Release.reset_password(admin.email, "newpass12345") end)
      assert output =~ "Password reset for"

      updated = Repo.get_by(Account, email: admin.email)
      refute Account.valid_password?(updated, @valid_password)
      assert Account.valid_password?(updated, "newpass12345")

      import Ecto.Query

      assert Repo.aggregate(
               from(t in AccountToken,
                 where: t.account_id == ^admin.id and t.context == "session"
               ),
               :count
             ) == 0
    end

    test "prints error for non-existent account" do
      output = capture_io(fn -> Release.reset_password("nobody@example.com", "newpass") end)
      assert output =~ "No account found"
    end
  end

  defp capture_io(fun) do
    ExUnit.CaptureIO.capture_io(fun)
  end
end
