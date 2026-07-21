defmodule CrmReactorWeb.CalendarFeedController do
  use CrmReactorWeb, :controller

  alias CrmReactor.Accounts
  alias CrmReactor.Calendar
  alias CrmReactor.Tenants.TenantCache

  def show(conn, %{"token" => token}) do
    with %{} = account <- Accounts.get_account_by_calendar_token(token),
         {:ok, %{schema_name: schema}} <- TenantCache.lookup(account.email) do
      ics = Calendar.build_feed(account, schema)

      conn
      |> put_resp_content_type("text/calendar")
      |> put_resp_header("cache-control", "no-cache, must-revalidate")
      |> send_resp(200, ics)
    else
      _ -> send_resp(conn, 404, "Not Found")
    end
  end
end
