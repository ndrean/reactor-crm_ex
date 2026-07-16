defmodule CrmReactorWeb.InviteControllerTest do
  use CrmReactorWeb.ConnCase

  alias CrmReactor.Accounts
  alias CrmReactor.Accounts.Account
  alias CrmReactor.Repo

  setup do
    # Create an unconfirmed user account (invite flow target)
    {:ok, account} =
      %Account{}
      |> Account.invite_changeset(%{
        email: "invited_#{System.unique_integer([:positive])}@test.com",
        name: "Invited User",
        role: "user",
        tenant_id: "test_tenant"
      })
      |> Repo.insert()

    {:ok, encoded_token} =
      Accounts.deliver_invite_email(account, "http://localhost:4002")

    %{account: account, token: encoded_token}
  end

  describe "GET /invite/:token" do
    test "renders invite form with valid token", %{conn: conn, token: token} do
      conn = get(conn, ~p"/invite/#{token}")
      assert html_response(conn, 200) =~ "password"
    end

    test "redirects with invalid token", %{conn: conn} do
      conn = get(conn, ~p"/invite/invalid-token")
      assert redirected_to(conn) == "/login"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "invalide"
    end

    test "redirects with expired/consumed token", %{conn: conn, token: token, account: _account} do
      # Accept the invite first (consumes token)
      {:ok, _} = Accounts.accept_invite(token, "newpassword123")

      conn = get(conn, ~p"/invite/#{token}")
      assert redirected_to(conn) == "/login"
    end
  end

  describe "POST /invite/:token" do
    test "accepts invite with valid token and password", %{conn: conn, token: token} do
      conn = post(conn, ~p"/invite/#{token}", %{"password" => "newpassword123"})
      # User role → redirects to /chat
      assert redirected_to(conn) == "/chat"
      assert get_session(conn, :account_token)
    end

    test "redirects with invalid token", %{conn: conn} do
      conn = post(conn, ~p"/invite/invalid-token", %{"password" => "newpassword123"})
      assert redirected_to(conn) == "/login"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "invalide"
    end
  end
end
