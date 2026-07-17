defmodule CrmReactorWeb.MetricsControllerTest do
  use CrmReactorWeb.ConnCase

  @admin_token Application.compile_env(:crm_reactor, :admin_token)

  test "GET /metrics returns prometheus text with valid token", %{conn: conn} do
    resp =
      conn
      |> put_req_header("authorization", "Bearer #{@admin_token}")
      |> get("/metrics")
      |> response(200)

    assert is_binary(resp)
  end

  test "GET /metrics returns 401 without token", %{conn: conn} do
    conn |> get("/metrics") |> response(401)
  end
end
