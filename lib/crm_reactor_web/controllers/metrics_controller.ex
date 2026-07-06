defmodule CrmReactorWeb.MetricsController do
  use CrmReactorWeb, :controller

  def index(conn, _params) do
    metrics = TelemetryMetricsPrometheus.Core.scrape(CrmReactor.PromEx.Metrics)

    conn
    |> put_resp_content_type("text/plain")
    |> send_resp(200, metrics)
  end
end
