defmodule CrmReactorWeb.HealthControllerTest do
  use CrmReactorWeb.ConnCase

  test "GET /api/health returns ok when database is up", %{conn: conn} do
    resp = conn |> get("/api/health") |> json_response(200)
    assert resp["status"] == "ok"
  end
end
