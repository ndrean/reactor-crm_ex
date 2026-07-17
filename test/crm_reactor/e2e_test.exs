defmodule CrmReactor.E2ETest do
  @moduledoc """
  End-to-end tests hitting the real Mistral API through the full
  Reactor pipeline. Mirrors the n8n bash smoke tests in test-api.sh.

  Run with: MISTRAL_API_KEY=... mix test --only external
  """
  use CrmReactorWeb.ConnCase

  alias CrmReactor.CRM.Contact

  @moduletag :external
  @admin_token "dev-admin-token"

  setup %{conn: conn} do
    # Use real classifier for this test module
    Application.put_env(:crm_reactor, :classifier, CrmReactor.AI.Classifier)

    on_exit(fn ->
      Application.put_env(:crm_reactor, :classifier, CrmReactor.AI.MockClassifier)
    end)

    tid = "__e2e_#{System.unique_integer([:positive])}"
    user_id = "5555555555"

    # Provision tenant via admin API
    admin_conn = put_req_header(conn, "authorization", "bearer #{@admin_token}")

    resp =
      admin_conn
      |> post("/api/admin/provision", %{
        tenant_id: tid,
        company_name: "E2E Test Corp",
        telegram_chat_id: user_id,
        email: "e2e_test@example.com"
      })
      |> json_response(200)

    schema = resp["schema_name"]

    # Seed 2 contacts + 2 todos
    for attrs <- [
          %{
            first_name: "Marie",
            last_name: "Dupont",
            phone: "0612345678",
            email: "marie@test.com",
            company_name: "TestCorp"
          },
          %{
            first_name: "Paul",
            last_name: "Martin",
            phone: "0698765432",
            email: "paul@test.com",
            company_name: "TestCorp"
          }
        ] do
      %Contact{} |> Contact.changeset(attrs) |> CrmReactor.Repo.insert!(prefix: schema)
    end

    tomorrow = Date.add(Date.utc_today(), 1)
    next_week = Date.add(Date.utc_today(), 7)

    CrmReactor.Repo.query!(
      "INSERT INTO #{schema}.todos (subject, due_date, created_by) VALUES ($1, $2, $3), ($4, $5, $6)",
      ["Appeler Marie Dupont", tomorrow, user_id, "Envoyer le rapport", next_week, user_id]
    )

    on_exit(fn ->
      CrmReactor.Repo.query!("DROP SCHEMA IF EXISTS #{schema} CASCADE")
      CrmReactor.Repo.query!("DELETE FROM global_registry.tenants WHERE tenant_id = '#{tid}'")

      CrmReactor.Repo.query!(
        "DELETE FROM global_registry.user_mappings WHERE email = 'e2e_test@example.com'"
      )
    end)

    %{user_id: user_id, tenant_id: tid, schema: schema, admin_conn: admin_conn}
  end

  defp crm_call(conn, user_id, text) do
    conn
    |> post("/api/crm", %{user_id: user_id, text: text})
    |> json_response(200)
  end

  defp crm_confirm(conn, pending_id, decision, user_id) do
    conn
    |> post("/api/crm/confirm", %{pending_id: pending_id, decision: decision, user_id: user_id})
    |> json_response(200)
  end

  # ── Contacts: read ──────────────────────────────────────────────────

  test "contacts: search by name", %{conn: conn, user_id: uid} do
    resp = crm_call(conn, uid, "cherche Marie Dupont")
    assert resp["output"] =~ "Marie"
  end

  test "contacts: count all", %{conn: conn, user_id: uid} do
    resp = crm_call(conn, uid, "combien de contacts")
    assert resp["output"] =~ "2"
  end

  # ── Contacts: mutations (2-step) ────────────────────────────────────

  test "contacts: update 2-step confirm", %{conn: conn, user_id: uid} do
    resp = crm_call(conn, uid, "modifie le téléphone de Marie Dupont à 0611111111")
    assert resp["pending_id"], "expected pending_id, got: #{inspect(resp)}"

    confirm_resp = crm_confirm(conn, resp["pending_id"], "confirm", uid)
    assert confirm_resp["output"] =~ "modifié"
  end

  test "contacts: delete 2-step reject", %{conn: conn, user_id: uid} do
    resp = crm_call(conn, uid, "supprime le contact Paul Martin")
    assert resp["pending_id"], "expected pending_id, got: #{inspect(resp)}"

    reject_resp = crm_confirm(conn, resp["pending_id"], "reject", uid)
    assert reject_resp["output"] =~ "annulée"
  end

  # ── Todos: read ─────────────────────────────────────────────────────

  test "todos: list all", %{conn: conn, user_id: uid} do
    resp = crm_call(conn, uid, "lister mes tâches")
    assert resp["action"] == "list"
    assert resp["output"] =~ "Appeler"
  end

  # ── Todos: create + complete ────────────────────────────────────────

  @tag :requires_mistral
  test "todos: create", %{conn: conn, user_id: uid} do
    resp = crm_call(conn, uid, "ajoute la tâche tester le système pour demain")
    assert resp["action"] == "create"
    assert resp["output"] =~ "créée"
  end

  test "todos: complete", %{conn: conn, user_id: uid} do
    resp = crm_call(conn, uid, "marque comme terminée la tâche Envoyer le rapport")
    assert resp["action"] == "complete"
  end

  # ── Todos: mutation (2-step) ────────────────────────────────────────

  @tag :requires_mistral
  test "todos: update 2-step confirm", %{conn: conn, user_id: uid} do
    future = Date.add(Date.utc_today(), 30) |> Date.to_string()

    resp =
      crm_call(conn, uid, "modifier la date de la tâche Envoyer le rapport au #{future}")

    assert resp["pending_id"], "expected pending_id, got: #{inspect(resp)}"

    confirm_resp = crm_confirm(conn, resp["pending_id"], "confirm", uid)
    assert confirm_resp["output"] =~ "modifiée"
  end

  # ── Help / routing ──────────────────────────────────────────────────

  test "help: aide", %{conn: conn, user_id: uid} do
    resp = crm_call(conn, uid, "aide")
    assert resp["output"]
  end

  test "routing: gibberish returns none", %{conn: conn, user_id: uid} do
    resp = crm_call(conn, uid, "blablabla test 123")
    assert resp["action"] in ["none", "help"]
  end

  test "routing: data export", %{conn: conn, user_id: uid} do
    resp = crm_call(conn, uid, "exporte mes données")
    assert resp["action"] != "none"
  end

  # ── Auth ────────────────────────────────────────────────────────────

  test "auth: unknown user rejected", %{conn: conn} do
    conn
    |> post("/api/crm", %{user_id: "0000000000", text: "aide"})
    |> json_response(403)
  end

  # ── Admin ───────────────────────────────────────────────────────────

  test "admin: provision without auth rejected", %{conn: conn} do
    conn
    |> post("/api/admin/provision", %{tenant_id: "x", company_name: "x"})
    |> json_response(401)
  end

  test "admin: deactivate locks out, reactivate restores", %{
    conn: conn,
    user_id: uid,
    tenant_id: tid,
    admin_conn: admin_conn
  } do
    # Deactivate
    resp =
      admin_conn
      |> post("/api/admin/toggle", %{tenant_id: tid, active: false})
      |> json_response(200)

    assert resp["is_active"] == false

    # Locked out
    conn |> post("/api/crm", %{user_id: uid, text: "aide"}) |> json_response(403)

    # Reactivate
    resp =
      admin_conn
      |> post("/api/admin/toggle", %{tenant_id: tid, active: true})
      |> json_response(200)

    assert resp["is_active"] == true

    # Works again
    resp = crm_call(conn, uid, "aide")
    assert resp["output"]
  end
end
