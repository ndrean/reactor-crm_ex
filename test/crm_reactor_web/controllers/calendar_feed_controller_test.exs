defmodule CrmReactorWeb.CalendarFeedControllerTest do
  use CrmReactorWeb.ConnCase

  alias CrmReactor.Accounts
  alias CrmReactor.Tenants.TenantCache

  setup do
    ctx = CrmReactor.TestFixtures.provision_test_tenant("cal_ctrl")
    on_exit(fn -> CrmReactor.TestFixtures.cleanup_tenant(ctx) end)

    TenantCache.reload()

    account = create_account(email: ctx.user_id, tenant_id: ctx.tenant.tenant_id)
    {:ok, Map.put(ctx, :account, account)}
  end

  describe "GET /cal/:token" do
    test "returns 200 with text/calendar for valid token", ctx do
      {:ok, token} = Accounts.generate_calendar_token(ctx.account)

      conn = build_conn() |> get("/cal/#{token}")

      assert conn.status == 200
      assert get_resp_header(conn, "content-type") |> hd() =~ "text/calendar"
      assert conn.resp_body =~ "BEGIN:VCALENDAR"
    end

    test "returns 404 for invalid token" do
      conn = build_conn() |> get("/cal/invalidtoken123")
      assert conn.status == 404
    end

    test "returns 404 for expired token", ctx do
      {:ok, token} = Accounts.generate_calendar_token(ctx.account)

      # Expire the token
      import Ecto.Query

      from(t in CrmReactor.Accounts.AccountToken,
        where: t.account_id == ^ctx.account.id and t.context == "calendar"
      )
      |> CrmReactor.Repo.update_all(
        set: [inserted_at: DateTime.add(DateTime.utc_now(), -366, :day)]
      )

      conn = build_conn() |> get("/cal/#{token}")
      assert conn.status == 404
    end

    test "sets no-cache headers", ctx do
      {:ok, token} = Accounts.generate_calendar_token(ctx.account)
      conn = build_conn() |> get("/cal/#{token}")

      assert get_resp_header(conn, "cache-control") |> hd() =~ "no-cache"
    end
  end
end
