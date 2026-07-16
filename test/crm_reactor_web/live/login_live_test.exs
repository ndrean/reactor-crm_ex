defmodule CrmReactorWeb.LoginLiveTest do
  use CrmReactorWeb.ConnCase

  import Phoenix.LiveViewTest

  describe "LoginLive" do
    test "renders login form", %{conn: conn} do
      {:ok, view, html} = live(conn, ~p"/login")
      assert html =~ "Se connecter"
      assert html =~ "Email"
      assert html =~ "Mot de passe"
      assert has_element?(view, "input[name='account[email]']")
      assert has_element?(view, "input[name='account[password]']")
    end

    test "validate event updates form", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/login")

      html =
        view
        |> element("#login-form")
        |> render_change(%{"account" => %{"email" => "test@example.com", "password" => "pass"}})

      assert html =~ "test@example.com"
    end

    test "login with invalid credentials flashes error", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/login")

      view
      |> element("#login-form")
      |> render_submit(%{"account" => %{"email" => "wrong@test.com", "password" => "wrong"}})

      assert render(view) =~ "Email ou mot de passe invalide"
    end

    test "login with valid credentials sets trigger_submit", %{conn: conn} do
      _account = create_account(%{email: "login_test@test.com", password: "password1234"})

      {:ok, view, _html} = live(conn, ~p"/login")

      html =
        view
        |> element("#login-form")
        |> render_submit(%{
          "account" => %{"email" => "login_test@test.com", "password" => "password1234"}
        })

      assert html =~ "phx-trigger-action"
    end

    test "redirects authenticated admin to /admin", %{conn: conn} do
      %{conn: conn} = register_and_log_in_admin(conn)
      assert {:error, {:redirect, %{to: "/admin"}}} = live(conn, ~p"/login")
    end

    test "redirects authenticated user to /chat", %{conn: conn} do
      %{conn: conn} = register_and_log_in_user(conn)
      assert {:error, {:redirect, %{to: "/chat"}}} = live(conn, ~p"/login")
    end
  end
end
