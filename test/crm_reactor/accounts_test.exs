defmodule CrmReactor.AccountsTest do
  use CrmReactor.DataCase

  alias CrmReactor.Accounts
  alias CrmReactor.Accounts.{Account, AccountToken}
  alias CrmReactor.Repo
  alias CrmReactor.Tenants.UserMapping

  @valid_password "password1234"

  defp create_confirmed_account(attrs \\ %{}) do
    email = attrs[:email] || "user_#{System.unique_integer([:positive])}@test.com"
    tenant_id = attrs[:tenant_id] || "test_tenant"

    {:ok, account} =
      %Account{}
      |> Account.registration_changeset(%{
        email: email,
        password: @valid_password,
        role: attrs[:role] || "user",
        tenant_id: tenant_id
      })
      |> Repo.insert()

    account
    |> Ecto.Changeset.change(%{confirmed_at: DateTime.utc_now() |> DateTime.truncate(:second)})
    |> Repo.update!()

    Repo.get!(Account, account.id)
  end

  # ── Login ──────────────────────────────────────────────────────────────

  describe "get_account_by_email_and_password/2" do
    test "returns account with valid credentials" do
      account = create_confirmed_account()
      assert found = Accounts.get_account_by_email_and_password(account.email, @valid_password)
      assert found.id == account.id
    end

    test "returns nil with wrong password" do
      account = create_confirmed_account()
      assert Accounts.get_account_by_email_and_password(account.email, "wrong") == nil
    end

    test "returns nil for suspended account" do
      account = create_confirmed_account()
      {:ok, _} = Accounts.suspend_account(account)
      assert Accounts.get_account_by_email_and_password(account.email, @valid_password) == nil
    end

    test "returns nil for nonexistent email" do
      assert Accounts.get_account_by_email_and_password("nobody@test.com", @valid_password) == nil
    end
  end

  # ── Session tokens ─────────────────────────────────────────────────────

  describe "session tokens" do
    test "generate and verify session token round-trip" do
      account = create_confirmed_account()
      token = Accounts.generate_account_session_token(account)
      assert found = Accounts.get_account_by_session_token(token)
      assert found.id == account.id
    end

    test "returns nil for invalid session token" do
      assert Accounts.get_account_by_session_token("invalid_token") == nil
    end

    test "delete_account_session_token invalidates the token" do
      account = create_confirmed_account()
      token = Accounts.generate_account_session_token(account)
      assert :ok = Accounts.delete_account_session_token(token)
      assert Accounts.get_account_by_session_token(token) == nil
    end
  end

  # ── Cross-tenant conflict ──────────────────────────────────────────────

  describe "check_email_tenant_conflict/2" do
    test "returns :ok when no conflict" do
      assert :ok = Accounts.check_email_tenant_conflict("new@test.com", "tenant_a")
    end

    test "returns :ok for nil email" do
      assert :ok = Accounts.check_email_tenant_conflict(nil, "tenant_a")
    end

    test "returns error when account email exists in different tenant" do
      account = create_confirmed_account(tenant_id: "tenant_a")

      assert {:error, "tenant_a"} =
               Accounts.check_email_tenant_conflict(account.email, "tenant_b")
    end

    test "returns error when mapping email exists in different tenant" do
      email = "mapped_#{System.unique_integer([:positive])}@test.com"

      %UserMapping{}
      |> UserMapping.changeset(%{
        tenant_id: "tenant_x",
        email: email
      })
      |> Repo.insert!()

      assert {:error, "tenant_x"} = Accounts.check_email_tenant_conflict(email, "tenant_y")
    end

    test "returns :ok when same tenant" do
      account = create_confirmed_account(tenant_id: "tenant_a")
      assert :ok = Accounts.check_email_tenant_conflict(account.email, "tenant_a")
    end
  end

  # ── Account creation ───────────────────────────────────────────────────

  describe "create_user_account/1" do
    test "creates account with mapping and reloads cache" do
      email = "new_user_#{System.unique_integer([:positive])}@test.com"

      {:ok, account} =
        Accounts.create_user_account(%{email: email, name: "Test", tenant_id: "test_tenant"})

      assert account.email == email
      assert account.role == "user"

      # Mapping should exist
      mapping = Repo.get_by(UserMapping, email: email)
      assert mapping
      assert mapping.tenant_id == "test_tenant"
    end

    test "returns error for tenant conflict" do
      account = create_confirmed_account(tenant_id: "tenant_a")

      {:error, changeset} =
        Accounts.create_user_account(%{email: account.email, name: "X", tenant_id: "tenant_b"})

      assert changeset.errors[:email]
    end
  end

  # ── Invite flow ────────────────────────────────────────────────────────

  describe "accept_invite/2" do
    test "sets password and confirms account with matching passwords" do
      {:ok, account} =
        %Account{}
        |> Account.invite_changeset(%{
          email: "inv_#{System.unique_integer([:positive])}@test.com",
          name: "Inv",
          role: "user",
          tenant_id: "test_tenant"
        })
        |> Repo.insert()

      {:ok, token} = Accounts.deliver_invite_email(account, "http://localhost:4002")

      {:ok, updated} =
        Accounts.accept_invite(token, %{
          password: "newpassword123",
          password_confirmation: "newpassword123"
        })

      assert updated.confirmed_at
      assert Account.valid_password?(updated, "newpassword123")
    end

    test "returns changeset error on password mismatch" do
      {:ok, account} =
        %Account{}
        |> Account.invite_changeset(%{
          email: "inv_mm_#{System.unique_integer([:positive])}@test.com",
          name: "Inv",
          role: "user",
          tenant_id: "test_tenant"
        })
        |> Repo.insert()

      {:ok, token} = Accounts.deliver_invite_email(account, "http://localhost:4002")

      assert {:error, %Ecto.Changeset{}} =
               Accounts.accept_invite(token, %{
                 password: "newpassword123",
                 password_confirmation: "different456"
               })
    end

    test "backward compat: accepts binary password" do
      {:ok, account} =
        %Account{}
        |> Account.invite_changeset(%{
          email: "inv_bc_#{System.unique_integer([:positive])}@test.com",
          name: "Inv",
          role: "user",
          tenant_id: "test_tenant"
        })
        |> Repo.insert()

      {:ok, token} = Accounts.deliver_invite_email(account, "http://localhost:4002")
      {:ok, updated} = Accounts.accept_invite(token, "newpassword123")
      assert updated.confirmed_at
    end

    test "returns error for invalid token" do
      assert {:error, :invalid_token} = Accounts.accept_invite("bad_token", "password123")
    end

    test "returns error for consumed token" do
      {:ok, account} =
        %Account{}
        |> Account.invite_changeset(%{
          email: "inv2_#{System.unique_integer([:positive])}@test.com",
          name: "Inv2",
          role: "user",
          tenant_id: "test_tenant"
        })
        |> Repo.insert()

      {:ok, token} = Accounts.deliver_invite_email(account, "http://localhost:4002")
      {:ok, _} = Accounts.accept_invite(token, "password123")
      assert {:error, :invalid_token} = Accounts.accept_invite(token, "password456")
    end
  end

  # ── Magic link login ─────────────────────────────────────────────────

  describe "deliver_magic_link_email/2" do
    test "returns :ok for existing account" do
      account = create_confirmed_account()
      assert :ok = Accounts.deliver_magic_link_email(account.email, "http://localhost:4002")
    end

    test "returns :ok for unknown email (no leak)" do
      assert :ok = Accounts.deliver_magic_link_email("nobody@test.com", "http://localhost:4002")
    end

    test "returns :ok for suspended account (no email sent)" do
      account = create_confirmed_account()
      {:ok, _} = Accounts.suspend_account(account)
      assert :ok = Accounts.deliver_magic_link_email(account.email, "http://localhost:4002")
    end
  end

  describe "login_by_magic_link/1" do
    test "returns account for valid token" do
      account = create_confirmed_account()
      {encoded, token_struct} = AccountToken.build_magic_link_token(account)
      Repo.insert!(token_struct)

      assert {:ok, found} = Accounts.login_by_magic_link(encoded)
      assert found.id == account.id
    end

    test "returns error for invalid token" do
      assert {:error, :invalid_token} = Accounts.login_by_magic_link("badtoken")
    end

    test "token is single-use" do
      account = create_confirmed_account()
      {encoded, token_struct} = AccountToken.build_magic_link_token(account)
      Repo.insert!(token_struct)

      assert {:ok, _} = Accounts.login_by_magic_link(encoded)
      assert {:error, :invalid_token} = Accounts.login_by_magic_link(encoded)
    end

    test "returns error for expired token" do
      account = create_confirmed_account()
      {encoded, token_struct} = AccountToken.build_magic_link_token(account)
      inserted = Repo.insert!(token_struct)

      # Manually expire the token
      from(t in AccountToken, where: t.id == ^inserted.id)
      |> Repo.update_all(set: [inserted_at: DateTime.add(DateTime.utc_now(), -20, :minute)])

      assert {:error, :invalid_token} = Accounts.login_by_magic_link(encoded)
    end
  end

  # ── Suspend / reactivate ───────────────────────────────────────────────

  describe "suspend and reactivate" do
    test "suspend sets suspended_at and clears sessions" do
      account = create_confirmed_account()
      token = Accounts.generate_account_session_token(account)

      {:ok, suspended} = Accounts.suspend_account(account)
      assert suspended.suspended_at

      # Session should be invalidated
      assert Accounts.get_account_by_session_token(token) == nil
    end

    test "reactivate clears suspended_at" do
      account = create_confirmed_account()
      {:ok, suspended} = Accounts.suspend_account(account)
      {:ok, reactivated} = Accounts.reactivate_account(suspended)
      assert reactivated.suspended_at == nil
    end
  end

  # ── Delete account ─────────────────────────────────────────────────────

  describe "delete_account/1" do
    test "removes account, tokens, and mapping" do
      email = "del_#{System.unique_integer([:positive])}@test.com"

      {:ok, account} =
        Accounts.create_user_account(%{email: email, name: "Del", tenant_id: "test_tenant"})

      _token = Accounts.generate_account_session_token(account)

      {:ok, _} = Accounts.delete_account(account)

      assert Repo.get(Account, account.id) == nil
      assert Repo.get_by(UserMapping, email: email) == nil
    end
  end

  # ── Queries ────────────────────────────────────────────────────────────

  describe "list_user_accounts/0" do
    test "returns only user-role accounts" do
      create_confirmed_account(role: "user")
      create_confirmed_account(role: "admin")

      accounts = Accounts.list_user_accounts()
      assert Enum.all?(accounts, &(&1.role == "user"))
    end
  end
end
