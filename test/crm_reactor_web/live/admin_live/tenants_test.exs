defmodule CrmReactorWeb.AdminLive.TenantsTest do
  use CrmReactorWeb.ConnCase

  import Phoenix.LiveViewTest

  alias CrmReactor.Repo
  alias CrmReactor.Tenants.{Provisioner, Tenant}

  setup %{conn: conn} do
    %{conn: conn} = register_and_log_in_admin(conn)
    %{conn: conn}
  end

  describe "mount" do
    test "renders provision form and tenant table", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/admin/tenants")
      assert html =~ "Tenants"
      assert html =~ "Tenant ID"
      assert html =~ "Company Name"
      assert html =~ "Provision"
    end
  end

  describe "provision event" do
    test "creates a new tenant", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin/tenants")
      tid = "test_prov_#{System.unique_integer([:positive])}"

      html =
        view
        |> element("#provision-form")
        |> render_submit(%{
          "tenant_id" => tid,
          "company_name" => "Test Provision Co",
          "admin_email" => ""
        })

      assert html =~ tid
      assert html =~ "Test Provision Co"

      # Cleanup
      tenant = Repo.get_by!(Tenant, tenant_id: tid)
      on_exit(fn -> Provisioner.drop_tenant(tenant) end)
    end

    test "invalid tenant ID flashes error", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin/tenants")

      view
      |> element("#provision-form")
      |> render_submit(%{
        "tenant_id" => "INVALID-ID!",
        "company_name" => "Bad Co",
        "admin_email" => ""
      })

      assert render(view) =~ "Invalid tenant ID"
    end
  end

  describe "toggle event" do
    test "toggles tenant active/inactive", %{conn: conn} do
      tid = "test_toggle_#{System.unique_integer([:positive])}"
      {:ok, tenant} = Provisioner.provision(tid, "Toggle Co", nil)
      on_exit(fn -> Provisioner.drop_tenant(tenant) end)

      {:ok, view, _html} = live(conn, ~p"/admin/tenants")

      # Deactivate
      view
      |> element("button[phx-click=toggle][phx-value-id=#{tid}]")
      |> render_click()

      assert render(view) =~ "deactivated"
    end
  end

  describe "set_webhook event" do
    test "sets webhook URL for tenant", %{conn: conn} do
      tid = "test_wh_#{System.unique_integer([:positive])}"
      {:ok, tenant} = Provisioner.provision(tid, "Webhook Co", nil)
      on_exit(fn -> Provisioner.drop_tenant(tenant) end)

      {:ok, view, _html} = live(conn, ~p"/admin/tenants")

      render_submit(view, "set_webhook", %{
        "tenant_id" => tid,
        "webhook_url" => "https://example.com/hook"
      })

      assert render(view) =~ "Webhook set"
    end
  end
end
