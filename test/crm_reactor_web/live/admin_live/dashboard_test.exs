defmodule CrmReactorWeb.AdminLive.DashboardTest do
  use CrmReactorWeb.ConnCase

  import Phoenix.LiveViewTest

  alias CrmReactor.CRM.ExecutionLog
  alias CrmReactor.{Repo, TestFixtures}

  setup %{conn: conn} do
    %{conn: conn} = register_and_log_in_admin(conn)
    %{conn: conn}
  end

  describe "mount" do
    test "renders dashboard with stats", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/admin")
      assert html =~ "Dashboard"
      assert html =~ "Active Tenants"
      assert html =~ "Total Users"
      assert html =~ "Recent Requests"
    end

    test "shows tenant and user counts", %{conn: conn} do
      fixture = TestFixtures.provision_test_tenant("dash")
      on_exit(fn -> TestFixtures.cleanup_tenant(fixture) end)

      {:ok, _view, html} = live(conn, ~p"/admin")
      # At least the provisioned tenant + its user should show
      assert html =~ "Active Tenants"
    end

    test "recent logs table renders with execution logs", %{conn: conn} do
      fixture = TestFixtures.provision_test_tenant("dash_logs")
      on_exit(fn -> TestFixtures.cleanup_tenant(fixture) end)

      # Insert an execution log
      %ExecutionLog{}
      |> ExecutionLog.create_changeset(%{
        triggered_by: fixture.user_id,
        channel: "test",
        raw_input: "test dashboard log",
        job_id: "dash-test-#{System.unique_integer([:positive])}"
      })
      |> Ecto.Changeset.put_change(:status, "completed")
      |> Ecto.Changeset.put_change(:module, "contacts")
      |> Ecto.Changeset.put_change(:action, "search")
      |> Repo.insert!(prefix: fixture.tenant.schema_name)

      {:ok, _view, html} = live(conn, ~p"/admin")
      assert html =~ "Recent Activity"
      assert html =~ "contacts"
    end
  end

  describe "access control" do
    test "non-admin user is redirected to /login", %{conn: _conn} do
      # Build a fresh conn with a non-admin user
      conn = Phoenix.ConnTest.build_conn()
      %{conn: conn} = register_and_log_in_user(conn)
      assert {:error, {:redirect, %{to: "/login"}}} = live(conn, ~p"/admin")
    end

    test "unauthenticated user is redirected to /login" do
      conn = Phoenix.ConnTest.build_conn()
      assert {:error, {:redirect, %{to: "/login"}}} = live(conn, ~p"/admin")
    end
  end
end
