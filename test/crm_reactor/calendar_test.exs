defmodule CrmReactor.CalendarTest do
  use CrmReactor.DataCase

  alias CrmReactor.Accounts
  alias CrmReactor.Accounts.{Account, AccountToken}
  alias CrmReactor.Calendar
  alias CrmReactor.Repo

  defp create_account(attrs \\ %{}) do
    email = attrs[:email] || "cal_#{System.unique_integer([:positive])}@test.com"

    {:ok, account} =
      %Account{}
      |> Account.registration_changeset(%{
        email: email,
        password: "password1234",
        role: "user",
        tenant_id: attrs[:tenant_id] || "test_tenant"
      })
      |> Repo.insert()

    Repo.get!(Account, account.id)
  end

  # ── AccountToken calendar functions ──────────────────────────────────

  describe "AccountToken calendar token" do
    test "build_calendar_token/1 creates a URL-safe token" do
      account = create_account()
      {encoded, struct} = AccountToken.build_calendar_token(account)

      assert is_binary(encoded)
      assert {:ok, _} = Base.url_decode64(encoded, padding: false)
      assert struct.context == "calendar"
      assert struct.account_id == account.id
    end

    test "verify_calendar_token_query/1 returns account for valid token" do
      account = create_account()
      {encoded, struct} = AccountToken.build_calendar_token(account)
      Repo.insert!(struct)

      assert {:ok, query} = AccountToken.verify_calendar_token_query(encoded)
      found = Repo.one(query)
      assert found.id == account.id
    end

    test "verify_calendar_token_query/1 returns :error for invalid base64" do
      assert :error = AccountToken.verify_calendar_token_query("!!!invalid!!!")
    end

    test "verify_calendar_token_query/1 returns nil for expired token" do
      account = create_account()
      {encoded, struct} = AccountToken.build_calendar_token(account)
      inserted = Repo.insert!(struct)

      # Expire the token (>365 days ago)
      from(t in AccountToken, where: t.id == ^inserted.id)
      |> Repo.update_all(set: [inserted_at: DateTime.add(DateTime.utc_now(), -366, :day)])

      assert {:ok, query} = AccountToken.verify_calendar_token_query(encoded)
      assert Repo.one(query) == nil
    end
  end

  # ── Accounts calendar context functions ──────────────────────────────

  describe "Accounts calendar functions" do
    test "get_or_create_calendar_token/1 is idempotent" do
      account = create_account()

      {:ok, token1} = Accounts.get_or_create_calendar_token(account)
      {:ok, token2} = Accounts.get_or_create_calendar_token(account)

      assert token1 == token2
    end

    test "get_account_by_calendar_token/1 returns account" do
      account = create_account()
      {:ok, token} = Accounts.generate_calendar_token(account)

      found = Accounts.get_account_by_calendar_token(token)
      assert found.id == account.id
    end

    test "get_account_by_calendar_token/1 returns nil for invalid token" do
      assert Accounts.get_account_by_calendar_token("badtoken") == nil
    end

    test "revoke_calendar_token/1 invalidates all calendar tokens" do
      account = create_account()
      {:ok, token} = Accounts.generate_calendar_token(account)

      :ok = Accounts.revoke_calendar_token(account)
      assert Accounts.get_account_by_calendar_token(token) == nil
    end

    test "revoke then get_or_create generates new token" do
      account = create_account()
      {:ok, token1} = Accounts.get_or_create_calendar_token(account)

      :ok = Accounts.revoke_calendar_token(account)
      {:ok, token2} = Accounts.get_or_create_calendar_token(account)

      assert token1 != token2
    end
  end

  # ── Calendar.build_feed/2 ───────────────────────────────────────────

  describe "build_feed/2" do
    setup do
      ctx = CrmReactor.TestFixtures.provision_test_tenant("calendar")
      on_exit(fn -> CrmReactor.TestFixtures.cleanup_tenant(ctx) end)
      {:ok, ctx}
    end

    test "generates valid ICS with VEVENT blocks", ctx do
      account = create_account(email: ctx.user_id, tenant_id: ctx.tenant.tenant_id)
      ics = Calendar.build_feed(account, ctx.tenant.schema_name)

      assert ics =~ "BEGIN:VCALENDAR"
      assert ics =~ "END:VCALENDAR"
      assert ics =~ "BEGIN:VEVENT"
      assert ics =~ "END:VEVENT"
    end

    test "includes timed appointment with DTSTART/DTEND", ctx do
      account = create_account(email: ctx.user_id, tenant_id: ctx.tenant.tenant_id)
      ics = Calendar.build_feed(account, ctx.tenant.schema_name)

      # The fixture creates "Réunion client" with starts_at
      assert ics =~ "Réunion client"
      assert ics =~ "DTSTART"
    end

    test "includes due-date todo as all-day event", ctx do
      account = create_account(email: ctx.user_id, tenant_id: ctx.tenant.tenant_id)
      ics = Calendar.build_feed(account, ctx.tenant.schema_name)

      # The fixture creates "Appeler fournisseur" with due_date
      assert ics =~ "Appeler fournisseur"
    end

    test "uses stable UIDs based on todo ID and tenant", ctx do
      account = create_account(email: ctx.user_id, tenant_id: ctx.tenant.tenant_id)
      ics = Calendar.build_feed(account, ctx.tenant.schema_name)

      tenant_id = String.replace_prefix(ctx.tenant.schema_name, "customer_", "")
      assert ics =~ "@#{tenant_id}.crm"
    end

    # VALARM removed: Apple Calendar breaks when first VEVENT has VALARM
    test "does not include VALARM blocks", ctx do
      account = create_account(email: ctx.user_id, tenant_id: ctx.tenant.tenant_id)
      ics = Calendar.build_feed(account, ctx.tenant.schema_name)

      refute ics =~ "BEGIN:VALARM"
    end

    test "uses CRLF line endings (RFC 5545)", ctx do
      account = create_account(email: ctx.user_id, tenant_id: ctx.tenant.tenant_id)
      ics = Calendar.build_feed(account, ctx.tenant.schema_name)

      # Every line should end with \r\n, no bare \n
      assert ics =~ "\r\n"
      stripped = String.replace(ics, "\r\n", "")
      refute stripped =~ "\n", "Found bare \\n without \\r"
    end

    test "excludes done and archived todos", ctx do
      import Ecto.Query
      schema = ctx.tenant.schema_name

      # Mark all todos as done
      from(t in CrmReactor.CRM.Todo, where: t.created_by == ^ctx.user_id)
      |> Repo.update_all([set: [done: true]], prefix: schema)

      account = create_account(email: ctx.user_id, tenant_id: ctx.tenant.tenant_id)
      ics = Calendar.build_feed(account, schema)

      refute ics =~ "BEGIN:VEVENT"
    end
  end
end
