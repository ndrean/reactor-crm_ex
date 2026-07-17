defmodule CrmReactorWeb.MetricsController do
  use CrmReactorWeb, :controller

  plug :verify_admin_token

  def index(conn, _params) do
    metrics =
      try do
        TelemetryMetricsPrometheus.Core.scrape(CrmReactor.PromEx.Metrics)
      catch
        :exit, _ -> ""
      end

    conn
    |> put_resp_content_type("text/plain")
    |> send_resp(200, metrics)
  end

  defp verify_admin_token(conn, _opts) do
    expected = Application.get_env(:crm_reactor, :admin_token)

    case get_req_header(conn, "authorization") do
      ["bearer " <> token] -> secure_check(conn, token, expected)
      ["Bearer " <> token] -> secure_check(conn, token, expected)
      _ -> conn |> send_resp(401, "Unauthorized") |> halt()
    end
  end

  defp secure_check(conn, token, expected) do
    if Plug.Crypto.secure_compare(token, expected) do
      conn
    else
      conn |> send_resp(401, "Unauthorized") |> halt()
    end
  end
end
