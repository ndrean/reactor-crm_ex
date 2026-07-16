defmodule CrmReactorWeb.Plugs.AccountAuthTest do
  use CrmReactorWeb.ConnCase

  alias CrmReactor.Accounts
  alias CrmReactorWeb.Plugs.AccountAuth

  setup %{conn: conn} do
    conn =
      conn
      |> Map.replace!(:secret_key_base, CrmReactorWeb.Endpoint.config(:secret_key_base))
      |> init_test_session(%{})

    %{conn: conn}
  end

  describe "fetch_current_account/2" do
    test "assigns nil when no token in session", %{conn: conn} do
      conn = AccountAuth.fetch_current_account(conn, [])
      assert conn.assigns.current_account == nil
    end

    test "assigns account when valid token in session", %{conn: conn} do
      account = create_account(%{role: "admin"})
      token = Accounts.generate_account_session_token(account)
      conn = conn |> put_session(:account_token, token) |> AccountAuth.fetch_current_account([])
      assert conn.assigns.current_account.id == account.id
    end

    test "assigns nil when token is invalid", %{conn: conn} do
      conn =
        conn |> put_session(:account_token, "invalid") |> AccountAuth.fetch_current_account([])

      assert conn.assigns.current_account == nil
    end
  end

  describe "require_authenticated_account/2" do
    test "passes through when account is present", %{conn: conn} do
      account = create_account()

      conn =
        conn |> assign(:current_account, account) |> AccountAuth.require_authenticated_account([])

      refute conn.halted
    end

    test "redirects to /login when no account", %{conn: conn} do
      conn =
        conn |> assign(:current_account, nil) |> AccountAuth.require_authenticated_account([])

      assert conn.halted
      assert redirected_to(conn) == "/login"
    end
  end

  describe "require_admin/2" do
    test "passes through when account is admin", %{conn: conn} do
      account = create_account(%{role: "admin"})
      conn = conn |> assign(:current_account, account) |> AccountAuth.require_admin([])
      refute conn.halted
    end

    test "redirects when account is user", %{conn: conn} do
      account = create_account(%{role: "user"})
      conn = conn |> assign(:current_account, account) |> AccountAuth.require_admin([])
      assert conn.halted
      assert redirected_to(conn) == "/login"
    end

    test "redirects when no account", %{conn: conn} do
      conn = conn |> assign(:current_account, nil) |> AccountAuth.require_admin([])
      assert conn.halted
      assert redirected_to(conn) == "/login"
    end
  end

  describe "redirect_if_authenticated/2" do
    test "redirects admin to /admin", %{conn: conn} do
      account = create_account(%{role: "admin"})

      conn =
        conn |> assign(:current_account, account) |> AccountAuth.redirect_if_authenticated([])

      assert conn.halted
      assert redirected_to(conn) == "/admin"
    end

    test "redirects user to /chat", %{conn: conn} do
      account = create_account(%{role: "user"})

      conn =
        conn |> assign(:current_account, account) |> AccountAuth.redirect_if_authenticated([])

      assert conn.halted
      assert redirected_to(conn) == "/chat"
    end

    test "passes through when unauthenticated", %{conn: conn} do
      conn = conn |> assign(:current_account, nil) |> AccountAuth.redirect_if_authenticated([])
      refute conn.halted
    end
  end

  describe "log_out_account/1" do
    test "clears session and redirects to /login", %{conn: conn} do
      account = create_account()
      token = Accounts.generate_account_session_token(account)

      conn =
        conn
        |> put_session(:account_token, token)
        |> AccountAuth.log_out_account()

      assert redirected_to(conn) == "/login"
      # Token should be deleted from DB
      assert Accounts.get_account_by_session_token(token) == nil
    end
  end
end
