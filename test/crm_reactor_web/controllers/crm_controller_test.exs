defmodule CrmReactorWeb.CrmControllerTest do
  use CrmReactorWeb.ConnCase

  alias CrmReactor.TestFixtures

  setup do
    fixture = TestFixtures.provision_test_tenant()
    on_exit(fn -> TestFixtures.cleanup_tenant(fixture) end)
    fixture
  end

  test "POST /api/crm - search contacts", %{conn: conn, user_id: user_id} do
    resp =
      conn
      |> post("/api/crm", %{user_id: user_id, text: "cherche Marie"})
      |> json_response(200)

    assert resp["output"] =~ "Marie"
    assert resp["action"] == "search"
  end

  test "POST /api/crm - unknown user returns 403", %{conn: conn} do
    conn
    |> post("/api/crm", %{user_id: "0000000000", text: "hello"})
    |> json_response(403)
  end

  test "POST /api/crm/confirm - confirms pending mutation", %{conn: conn, user_id: user_id} do
    resp =
      conn
      |> post("/api/crm", %{user_id: user_id, text: "supprime Marie Dupont"})
      |> json_response(200)

    assert resp["pending_id"]

    confirm_resp =
      conn
      |> post("/api/crm/confirm", %{pending_id: resp["pending_id"], decision: "confirm"})
      |> json_response(200)

    assert confirm_resp["output"] =~ "supprimé"
  end

  test "POST /api/crm/confirm - reject pending mutation", %{conn: conn, user_id: user_id} do
    resp =
      conn
      |> post("/api/crm", %{user_id: user_id, text: "supprime Marie Dupont"})
      |> json_response(200)

    confirm_resp =
      conn
      |> post("/api/crm/confirm", %{pending_id: resp["pending_id"], decision: "reject"})
      |> json_response(200)

    assert confirm_resp["output"] =~ "annulée"
  end

  test "POST /api/crm/confirm - not found returns 404", %{conn: conn} do
    conn
    |> post("/api/crm/confirm", %{
      pending_id: Ecto.UUID.generate(),
      decision: "confirm"
    })
    |> json_response(404)
  end

  test "POST /api/crm/confirm - invalid decision returns 400", %{conn: conn, user_id: user_id} do
    resp =
      conn
      |> post("/api/crm", %{user_id: user_id, text: "supprime Marie Dupont"})
      |> json_response(200)

    assert resp["pending_id"]

    confirm_resp =
      conn
      |> post("/api/crm/confirm", %{
        pending_id: resp["pending_id"],
        decision: "gibberish"
      })
      |> json_response(400)

    assert confirm_resp["error"] =~ "decision"
  end

  test "POST /api/crm/confirm - invalid email returns 400", %{conn: conn, user_id: user_id} do
    # Trigger export email pending
    resp =
      conn
      |> post("/api/crm", %{user_id: user_id, text: "exporte mes données"})
      |> json_response(200)

    assert resp["action"] == "pending"
    assert resp["pending_id"]

    confirm_resp =
      conn
      |> post("/api/crm/confirm", %{
        pending_id: resp["pending_id"],
        decision: "notanemail"
      })
      |> json_response(400)

    assert confirm_resp["error"] =~ "email"
  end
end
