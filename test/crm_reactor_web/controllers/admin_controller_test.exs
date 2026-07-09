defmodule CrmReactorWeb.AdminControllerTest do
  use CrmReactorWeb.ConnCase
  alias CrmReactor.AI.SubscriptionCache

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

  describe "PUT /api/admin/webhook" do
    test "sets webhook URL and returns it", %{conn: conn} do
      fixture = CrmReactor.TestFixtures.provision_test_tenant("wh")
      on_exit(fn -> CrmReactor.TestFixtures.cleanup_tenant(fixture) end)

      resp =
        conn
        |> put("/api/admin/webhook", %{
          tenant_id: fixture.tenant.tenant_id,
          webhook_url: "https://example.com/hook"
        })
        |> json_response(200)

      assert resp["success"] == true
      assert resp["webhook_url"] == "https://example.com/hook"
    end

    test "returns 404 for unknown tenant", %{conn: conn} do
      conn
      |> put("/api/admin/webhook", %{
        tenant_id: "nonexistent_tenant_xyz",
        webhook_url: "https://example.com/hook"
      })
      |> json_response(404)
    end

    test "returns 400 when params are missing", %{conn: conn} do
      conn
      |> put("/api/admin/webhook", %{tenant_id: "x"})
      |> json_response(400)
    end
  end

  describe "GET /api/admin/webhook_secret" do
    test "returns webhook secret after setting webhook", %{conn: conn} do
      fixture = CrmReactor.TestFixtures.provision_test_tenant("whs")
      on_exit(fn -> CrmReactor.TestFixtures.cleanup_tenant(fixture) end)

      conn
      |> put("/api/admin/webhook", %{
        tenant_id: fixture.tenant.tenant_id,
        webhook_url: "https://example.com/hook"
      })
      |> json_response(200)

      resp =
        conn
        |> get("/api/admin/webhook_secret", %{tenant_id: fixture.tenant.tenant_id})
        |> json_response(200)

      assert is_binary(resp["webhook_secret"])
      assert String.length(resp["webhook_secret"]) == 64
    end

    test "returns 404 for unknown tenant", %{conn: conn} do
      conn
      |> get("/api/admin/webhook_secret", %{tenant_id: "nonexistent_tenant_xyz"})
      |> json_response(404)
    end

    test "returns 404 when no webhook configured", %{conn: conn} do
      fixture = CrmReactor.TestFixtures.provision_test_tenant("whn")
      on_exit(fn -> CrmReactor.TestFixtures.cleanup_tenant(fixture) end)

      conn
      |> get("/api/admin/webhook_secret", %{tenant_id: fixture.tenant.tenant_id})
      |> json_response(404)
    end
  end

  describe "PUT /api/admin/subscriptions" do
    test "disables a workflow for a tenant", %{conn: conn} do
      tid = "sub_ctrl_test_#{System.unique_integer([:positive])}"

      on_exit(fn ->
        CrmReactor.Repo.query!(
          "DELETE FROM global_registry.tenant_workflow_overrides WHERE tenant_id = '#{tid}'"
        )
      end)

      resp =
        conn
        |> put("/api/admin/subscriptions", %{
          tenant_id: tid,
          workflow_name: "contacts",
          enabled: false
        })
        |> json_response(200)

      assert resp["success"] == true
      assert resp["tenant_id"] == tid
      assert resp["workflow_name"] == "contacts"
      assert resp["enabled"] == false
      assert SubscriptionCache.enabled?(tid, "contacts") == false
    end

    test "re-enables a workflow for a tenant", %{conn: conn} do
      tid = "sub_ctrl_test_#{System.unique_integer([:positive])}"

      on_exit(fn ->
        CrmReactor.Repo.query!(
          "DELETE FROM global_registry.tenant_workflow_overrides WHERE tenant_id = '#{tid}'"
        )
      end)

      conn
      |> put("/api/admin/subscriptions", %{tenant_id: tid, workflow_name: "todos", enabled: false})
      |> json_response(200)

      resp =
        conn
        |> put("/api/admin/subscriptions", %{
          tenant_id: tid,
          workflow_name: "todos",
          enabled: true
        })
        |> json_response(200)

      assert resp["enabled"] == true
      assert SubscriptionCache.enabled?(tid, "todos") == true
    end

    test "returns 400 when params are missing", %{conn: conn} do
      resp =
        conn
        |> put("/api/admin/subscriptions", %{tenant_id: "x"})
        |> json_response(400)

      assert resp["error"] =~ "required"
    end

    test "returns 401 without auth token" do
      build_conn()
      |> put_req_header("content-type", "application/json")
      |> put("/api/admin/subscriptions", %{
        tenant_id: "x",
        workflow_name: "contacts",
        enabled: false
      })
      |> json_response(401)
    end
  end
end
