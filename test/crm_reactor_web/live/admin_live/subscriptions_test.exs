defmodule CrmReactorWeb.AdminLive.SubscriptionsTest do
  use CrmReactorWeb.ConnCase

  import Phoenix.LiveViewTest

  alias CrmReactor.TestFixtures

  setup %{conn: conn} do
    %{conn: conn} = register_and_log_in_admin(conn)

    fixture = TestFixtures.provision_test_tenant("subs")
    on_exit(fn -> TestFixtures.cleanup_tenant(fixture) end)

    %{conn: conn, fixture: fixture}
  end

  describe "mount" do
    test "renders subscription matrix", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/admin/subscriptions")
      assert html =~ "Workflow Subscriptions"
      assert html =~ "Tenant"
    end
  end

  describe "toggle event" do
    test "disables and re-enables workflow for tenant", %{conn: conn, fixture: fixture} do
      {:ok, view, _html} = live(conn, ~p"/admin/subscriptions")
      tid = fixture.tenant.tenant_id

      # Disable the "contacts" workflow specifically
      html =
        view
        |> element(
          "button[phx-click=toggle][phx-value-tenant=#{tid}][phx-value-workflow=contacts]"
        )
        |> render_click()

      assert html =~ "disabled"

      # Re-enable
      html =
        view
        |> element(
          "button[phx-click=toggle][phx-value-tenant=#{tid}][phx-value-workflow=contacts]"
        )
        |> render_click()

      assert html =~ "enabled"
    end
  end
end
