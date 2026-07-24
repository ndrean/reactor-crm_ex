defmodule CrmReactorWeb.AdminLive.SystemTest do
  use CrmReactorWeb.ConnCase

  import Phoenix.LiveViewTest

  setup %{conn: conn} do
    %{conn: conn} = register_and_log_in_admin(conn)
    %{conn: conn}
  end

  describe "System page" do
    test "mounts and shows sections", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/admin/system")

      assert html =~ "System Status"
      assert html =~ "Domain Configuration"
      assert html =~ "Telegram Webhook"
      assert html =~ "Admin Accounts"
    end

    test "displays domain info", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/admin/system")

      assert html =~ "PHX_HOST"
      assert html =~ "Base URL"
      assert html =~ "Calendar Feed"
    end

    test "shows refresh and fix webhook buttons", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/admin/system")

      assert html =~ "Refresh"
      assert html =~ "Fix Webhook"
    end

    test "shows admin accounts section", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/admin/system")

      assert html =~ "Admin Accounts"
    end
  end
end
