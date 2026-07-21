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

  describe "list_admins/0" do
    test "prints message when no admins exist" do
      Repo.delete_all(AccountToken)
      Repo.delete_all(Account)

      output = capture_io(fn -> Release.list_admins() end)
      assert output =~ "No admin accounts found."
    end

    test "lists existing admin accounts" do
      Repo.delete_all(AccountToken)
      Repo.delete_all(Account)
      admin = create_admin("listtest@example.com")

      output = capture_io(fn -> Release.list_admins() end)
      assert output =~ admin.email
      assert output =~ "Total: 1"
    end
  end

  describe "delete_admin/1" do
    test "deletes an admin and revokes tokens" do
      Repo.delete_all(AccountToken)
      Repo.delete_all(Account)
      admin1 = create_admin("admin1@example.com")
      _admin2 = create_admin("admin2@example.com")

      # Create a session token
      {token, token_struct} = AccountToken.build_session_token(admin1)
      Repo.insert!(token_struct)
      assert Repo.get_by(AccountToken, token: token)

      output = capture_io(fn -> Release.delete_admin("admin1@example.com") end)
      assert output =~ "Deleted admin account"
      refute Repo.get_by(Account, email: "admin1@example.com")
      refute Repo.get_by(AccountToken, token: token)
    end

    test "refuses to delete the last admin" do
      Repo.delete_all(AccountToken)
      Repo.delete_all(Account)
      create_admin("sole@example.com")

      output = capture_io(fn -> Release.delete_admin("sole@example.com") end)
      assert output =~ "Cannot delete the last admin"
      assert Repo.get_by(Account, email: "sole@example.com")
    end

    test "prints error for non-existent admin" do
      output = capture_io(fn -> Release.delete_admin("nobody@example.com") end)
      assert output =~ "No admin account found"
    end
  end

  describe "reset_password/2" do
    test "resets password and revokes session tokens" do
      Repo.delete_all(AccountToken)
      Repo.delete_all(Account)
      admin = create_admin("reset@example.com")

      {_token, token_struct} = AccountToken.build_session_token(admin)
      Repo.insert!(token_struct)

      output = capture_io(fn -> Release.reset_password("reset@example.com", "newpass12345") end)
      assert output =~ "Password reset for"

      # Old password no longer works
      updated = Repo.get_by(Account, email: "reset@example.com")
      refute Account.valid_password?(updated, @valid_password)
      assert Account.valid_password?(updated, "newpass12345")

      # Session tokens revoked
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
