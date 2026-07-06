defmodule CrmReactorWeb.AdminControllerTest do
  use CrmReactorWeb.ConnCase

  @admin_token "dev-admin-token"

  setup %{conn: conn} do
    conn = put_req_header(conn, "authorization", "bearer #{@admin_token}")
    {:ok, conn: conn}
  end

  test "POST /api/admin/provision - creates tenant", %{conn: conn} do
    tid = "admin_test_#{System.unique_integer([:positive])}"

    resp =
      conn
      |> post("/api/admin/provision", %{
        tenant_id: tid,
        company_name: "Admin Test Corp",
        telegram_chat_id: "9999999999"
      })
      |> json_response(200)

    assert resp["success"] == true
    assert resp["schema_name"] == "customer_#{tid}"

    on_exit(fn ->
      CrmReactor.Repo.query!("DROP SCHEMA IF EXISTS customer_#{tid} CASCADE")
      CrmReactor.Repo.query!("DELETE FROM global_registry.tenants WHERE tenant_id = '#{tid}'")

      CrmReactor.Repo.query!(
        "DELETE FROM global_registry.user_mappings WHERE tenant_id = '#{tid}'"
      )
    end)
  end

  test "POST /api/admin/provision - rejected without auth token", %{conn: _conn} do
    build_conn()
    |> put_req_header("content-type", "application/json")
    |> post("/api/admin/provision", %{tenant_id: "x", company_name: "X"})
    |> json_response(401)
  end

  test "POST /api/admin/toggle - deactivate and reactivate", %{conn: conn} do
    tid = "toggle_test_#{System.unique_integer([:positive])}"

    conn
    |> post("/api/admin/provision", %{tenant_id: tid, company_name: "Toggle Corp"})
    |> json_response(200)

    resp =
      conn |> post("/api/admin/toggle", %{tenant_id: tid, active: false}) |> json_response(200)

    assert resp["is_active"] == false

    resp =
      conn |> post("/api/admin/toggle", %{tenant_id: tid, active: true}) |> json_response(200)

    assert resp["is_active"] == true

    on_exit(fn ->
      CrmReactor.Repo.query!("DROP SCHEMA IF EXISTS customer_#{tid} CASCADE")
      CrmReactor.Repo.query!("DELETE FROM global_registry.tenants WHERE tenant_id = '#{tid}'")

      CrmReactor.Repo.query!(
        "DELETE FROM global_registry.user_mappings WHERE tenant_id = '#{tid}'"
      )
    end)
  end

  test "POST /api/admin/toggle - not found returns 404", %{conn: conn} do
    conn
    |> post("/api/admin/toggle", %{tenant_id: "nonexistent_tenant_xyz", active: false})
    |> json_response(404)
  end

  test "GET /api/admin/subjects/:id/export - returns subject data", %{conn: conn} do
    fixture = CrmReactor.TestFixtures.provision_test_tenant()
    on_exit(fn -> CrmReactor.TestFixtures.cleanup_tenant(fixture) end)

    resp =
      conn
      |> get("/api/admin/subjects/#{fixture.user_id}/export")
      |> json_response(200)

    assert resp["user_identifier"] == fixture.user_id
  end

  test "GET /api/admin/subjects/:id/export - not found returns 404", %{conn: conn} do
    conn
    |> get("/api/admin/subjects/unknown_user_xyz/export")
    |> json_response(404)
  end

  test "POST /api/admin/subjects/:id/email-export - no email returns 422", %{conn: conn} do
    fixture = CrmReactor.TestFixtures.provision_test_tenant()
    on_exit(fn -> CrmReactor.TestFixtures.cleanup_tenant(fixture) end)

    resp =
      conn
      |> post("/api/admin/subjects/#{fixture.user_id}/email-export")
      |> json_response(422)

    assert resp["error"] =~ "email"
  end

  test "POST /api/admin/subjects/:id/email-export - not found returns 404", %{conn: conn} do
    conn
    |> post("/api/admin/subjects/unknown_user_xyz/email-export")
    |> json_response(404)
  end

  test "DELETE /api/admin/subjects/:id - erases subject data", %{conn: conn} do
    fixture = CrmReactor.TestFixtures.provision_test_tenant()
    on_exit(fn -> CrmReactor.TestFixtures.cleanup_tenant(fixture) end)

    resp =
      conn
      |> delete("/api/admin/subjects/#{fixture.user_id}")
      |> json_response(200)

    assert resp["success"] == true
    assert resp["erased"] == fixture.user_id
  end

  test "DELETE /api/admin/subjects/:id - not found returns 404", %{conn: conn} do
    conn
    |> delete("/api/admin/subjects/unknown_user_xyz")
    |> json_response(404)
  end

  test "DELETE /api/admin/contacts/:schema/:contact_id - erases contact", %{conn: conn} do
    fixture = CrmReactor.TestFixtures.provision_test_tenant()
    on_exit(fn -> CrmReactor.TestFixtures.cleanup_tenant(fixture) end)

    [contact | _] =
      CrmReactor.Repo.all(CrmReactor.CRM.Contact, prefix: fixture.tenant.schema_name)

    resp =
      conn
      |> delete("/api/admin/contacts/#{fixture.tenant.schema_name}/#{contact.id}")
      |> json_response(200)

    assert resp["success"] == true
  end

  test "DELETE /api/admin/contacts/:schema/:contact_id - not found returns 404", %{conn: conn} do
    fixture = CrmReactor.TestFixtures.provision_test_tenant()
    on_exit(fn -> CrmReactor.TestFixtures.cleanup_tenant(fixture) end)

    conn
    |> delete("/api/admin/contacts/#{fixture.tenant.schema_name}/999999999")
    |> json_response(404)
  end
end
