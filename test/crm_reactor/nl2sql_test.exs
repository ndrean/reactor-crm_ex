defmodule CrmReactor.NL2SQLTest do
  @moduledoc """
  Tests the NL2SQL escalation path with real Mistral API.
  Covers multi-result searches, date-relative queries, compound filters.

  Run with: MISTRAL_API_KEY=... mix test --only external
  """
  use CrmReactorWeb.ConnCase

  alias CrmReactor.CRM.Contact

  @moduletag :external

  setup %{conn: conn} do
    Application.put_env(:crm_reactor, :classifier, CrmReactor.AI.Classifier)

    on_exit(fn ->
      Application.put_env(:crm_reactor, :classifier, CrmReactor.AI.MockClassifier)
    end)

    tid = "__nl2sql_#{System.unique_integer([:positive])}"
    user_id = "6666666666"
    admin_conn = put_req_header(conn, "authorization", "bearer dev-admin-token")

    resp =
      admin_conn
      |> post("/api/admin/provision", %{
        tenant_id: tid,
        company_name: "NL2SQL Test Corp",
        telegram_chat_id: user_id,
        email: "nl2sql_test@example.com"
      })
      |> json_response(200)

    schema = resp["schema_name"]

    for attrs <- [
          %{
            first_name: "Jean",
            last_name: "Dupont",
            phone: "0612345678",
            email: "jean.d@test.com",
            company_name: "Acme"
          },
          %{
            first_name: "Jean",
            last_name: "Martin",
            phone: "0698765432",
            email: "jean.m@test.com",
            company_name: "Acme"
          },
          %{
            first_name: "Marie",
            last_name: "Dupont",
            phone: "0611111111",
            email: "marie@test.com",
            company_name: "BigCorp"
          },
          %{
            first_name: "Paul",
            last_name: "Bernard",
            phone: "0622222222",
            email: "paul@test.com",
            company_name: "Acme"
          }
        ] do
      %Contact{} |> Contact.changeset(attrs) |> CrmReactor.Repo.insert!(prefix: schema)
    end

    today = Date.utc_today()
    tomorrow = Date.add(today, 1)
    day_after = Date.add(today, 2)
    next_week = Date.add(today, 7)

    CrmReactor.Repo.query!(
      """
      INSERT INTO #{schema}.todos (subject, due_date, created_by)
      VALUES ($1, $2, $3), ($4, $5, $6), ($7, $8, $9), ($10, $11, $12)
      """,
      [
        "Appeler Jean Dupont",
        tomorrow,
        user_id,
        "Envoyer devis Acme",
        tomorrow,
        user_id,
        "Réunion équipe",
        day_after,
        user_id,
        "Bilan mensuel",
        next_week,
        user_id
      ]
    )

    on_exit(fn ->
      CrmReactor.Repo.query!("DROP SCHEMA IF EXISTS #{schema} CASCADE")
      CrmReactor.Repo.query!("DELETE FROM global_registry.tenants WHERE tenant_id = '#{tid}'")

      CrmReactor.Repo.query!(
        "DELETE FROM global_registry.user_mappings WHERE email = 'nl2sql_test@example.com'"
      )
    end)

    %{user_id: user_id, schema: schema}
  end

  defp crm_call(conn, user_id, text) do
    conn
    |> post("/api/crm", %{user_id: user_id, text: text})
    |> json_response(200)
  end

  # ── Contacts: multi-result searches ─────────────────────────────────

  test "contacts: search 'Jean' returns multiple results", %{conn: conn, user_id: uid} do
    resp = crm_call(conn, uid, "trouver les contacts avec Jean")
    assert resp["output"] =~ "Jean"
    assert resp["output"] =~ "Dupont"
    assert resp["output"] =~ "Martin"
  end

  test "contacts: search by company returns all from that company", %{conn: conn, user_id: uid} do
    resp = crm_call(conn, uid, "tous les contacts chez Acme")
    assert resp["output"] =~ "Jean"
    assert resp["output"] =~ "Paul"
  end

  test "contacts: search 'Dupont' returns Jean and Marie", %{conn: conn, user_id: uid} do
    resp = crm_call(conn, uid, "cherche les Dupont")
    assert resp["output"] =~ "Jean"
    assert resp["output"] =~ "Marie"
  end

  # ── Todos: date-relative queries ────────────────────────────────────

  @tag :requires_mistral
  test "todos: list tasks for tomorrow", %{conn: conn, user_id: uid} do
    resp = crm_call(conn, uid, "quelles sont mes tâches pour demain")
    assert resp["output"] =~ "Appeler"
    assert resp["output"] =~ "devis"
    refute resp["output"] =~ "Bilan"
  end

  @tag :requires_mistral
  test "todos: list tasks until day after tomorrow", %{conn: conn, user_id: uid} do
    resp = crm_call(conn, uid, "mes tâches jusqu'à après-demain")
    assert resp["output"] =~ "Appeler"
    assert resp["output"] =~ "Réunion"
    refute resp["output"] =~ "Bilan"
  end

  @tag :requires_mistral
  test "todos: list all tasks", %{conn: conn, user_id: uid} do
    resp = crm_call(conn, uid, "liste toutes mes tâches")
    assert resp["output"] =~ "Appeler"
    assert resp["output"] =~ "Bilan"
  end
end
