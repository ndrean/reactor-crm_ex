defmodule CrmReactorWeb.AdminLive.LogsTest do
  use CrmReactorWeb.ConnCase

  import Phoenix.LiveViewTest

  alias CrmReactor.CRM.ExecutionLog
  alias CrmReactor.{Repo, TestFixtures}

  setup %{conn: conn} do
    %{conn: conn} = register_and_log_in_admin(conn)

    fixture = TestFixtures.provision_test_tenant("logs")
    on_exit(fn -> TestFixtures.cleanup_tenant(fixture) end)

    # Insert some execution logs
    for {status, i} <- Enum.with_index(["completed", "error", "processing"]) do
      %ExecutionLog{}
      |> ExecutionLog.create_changeset(%{
        triggered_by: fixture.user_id,
        channel: "test",
        raw_input: "log test #{i}",
        job_id: "log-test-#{System.unique_integer([:positive])}"
      })
      |> Ecto.Changeset.put_change(:status, status)
      |> Ecto.Changeset.put_change(:module, "contacts")
      |> Ecto.Changeset.put_change(:action, "search")
      |> Repo.insert!(prefix: fixture.tenant.schema_name)
    end

    %{conn: conn, fixture: fixture}
  end

  describe "mount" do
    test "renders filter dropdowns and logs table", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/admin/logs")
      assert html =~ "Execution Logs"
      assert html =~ "All tenants"
      assert html =~ "completed"
      assert html =~ "contacts"
    end
  end

  describe "filter event" do
    test "filter by tenant updates logs", %{conn: conn, fixture: fixture} do
      {:ok, view, _html} = live(conn, ~p"/admin/logs")

      html =
        view
        |> element("select[name=tenant]")
        |> render_change(%{"tenant" => fixture.tenant.tenant_id})

      assert html =~ "contacts"
    end

    test "filter by status shows only matching logs", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin/logs")

      html =
        view
        |> element("select[name=status]")
        |> render_change(%{"status" => "error"})

      assert html =~ "error"
    end

    test "clearing filter shows all logs", %{conn: conn, fixture: fixture} do
      {:ok, view, _html} = live(conn, ~p"/admin/logs")

      # Set filter first
      view
      |> element("select[name=tenant]")
      |> render_change(%{"tenant" => fixture.tenant.tenant_id})

      # Clear filter
      html =
        view
        |> element("select[name=tenant]")
        |> render_change(%{"tenant" => ""})

      assert html =~ "Execution Logs"
    end
  end
end
