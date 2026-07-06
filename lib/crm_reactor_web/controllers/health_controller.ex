defmodule CrmReactorWeb.HealthController do
  use CrmReactorWeb, :controller

  alias Ecto.Adapters.SQL

  def check(conn, _params) do
    case SQL.query(CrmReactor.Repo, "SELECT 1") do
      {:ok, _} -> json(conn, %{status: "ok"})
      _ -> conn |> put_status(503) |> json(%{status: "unhealthy"})
    end
  end
end
