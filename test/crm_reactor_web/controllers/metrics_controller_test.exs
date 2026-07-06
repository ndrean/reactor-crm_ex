defmodule CrmReactorWeb.MetricsControllerTest do
  use CrmReactorWeb.ConnCase

  test "GET /metrics returns prometheus text", %{conn: conn} do
    resp = conn |> get("/metrics") |> response(200)
    assert is_binary(resp)
  end
end
