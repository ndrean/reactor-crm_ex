defmodule CrmReactorWeb.AccountSessionControllerTest do
  use CrmReactorWeb.ConnCase

  setup %{conn: conn} do
    account = create_account(%{email: "session@test.com", password: "password1234", role: "user"})
    %{conn: conn, account: account}
  end

  describe "GET /" do
    test "redirects to /login", %{conn: conn} do
      conn = get(conn, ~p"/")
      assert redirected_to(conn) == "/login"
    end
  end

  describe "POST /login" do
    test "logs in with valid credentials and redirects", %{conn: conn, account: account} do
      conn =
        post(conn, ~p"/login", %{
          "account" => %{"email" => account.email, "password" => "password1234"}
        })

      assert redirected_to(conn) == "/chat"
      assert get_session(conn, :account_token)
    end

    test "redirects to /login with flash on invalid credentials", %{conn: conn} do
      conn =
        post(conn, ~p"/login", %{
          "account" => %{"email" => "wrong@test.com", "password" => "wrong"}
        })

      assert redirected_to(conn) == "/login"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "invalide"
    end

    test "admin redirects to /admin on login", %{conn: conn} do
      admin =
        create_account(%{email: "admin_sess@test.com", password: "password1234", role: "admin"})

      conn =
        post(conn, ~p"/login", %{
          "account" => %{"email" => admin.email, "password" => "password1234"}
        })

      assert redirected_to(conn) == "/admin"
    end
  end

  describe "GET /login/magic/:token" do
    test "logs in with valid magic link token", %{conn: conn, account: account} do
      {encoded, token_struct} =
        CrmReactor.Accounts.AccountToken.build_magic_link_token(account)

      CrmReactor.Repo.insert!(token_struct)

      conn = get(conn, ~p"/login/magic/#{encoded}")
      assert redirected_to(conn) == "/chat"
      assert get_session(conn, :account_token)
    end

    test "redirects with flash on invalid token", %{conn: conn} do
      conn = get(conn, ~p"/login/magic/invalidtoken")
      assert redirected_to(conn) == "/login"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "invalide ou expiré"
    end
  end

  describe "DELETE /logout" do
    test "logs out and redirects to /login", %{conn: conn, account: account} do
      conn = log_in_account(conn, account)
      conn = delete(conn, ~p"/logout")
      assert redirected_to(conn) == "/login"
    end
  end
end
