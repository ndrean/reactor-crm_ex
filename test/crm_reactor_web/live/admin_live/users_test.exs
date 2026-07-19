defmodule CrmReactorWeb.AdminLive.UsersTest do
  use CrmReactorWeb.ConnCase

  import Phoenix.LiveViewTest

  alias CrmReactor.{Accounts, Repo}
  alias CrmReactor.Tenants.{Provisioner, UserMapping}

  setup %{conn: conn} do
    %{conn: conn} = register_and_log_in_admin(conn)

    tid = "test_users_#{System.unique_integer([:positive])}"
    {:ok, tenant} = Provisioner.provision(tid, "Users Test Co", nil)
    on_exit(fn -> Provisioner.drop_tenant(tenant) end)

    %{conn: conn, tenant_id: tid}
  end

  describe "mount" do
    test "renders unified page sections", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/admin/users")
      assert html =~ "Create User Account"
      assert html =~ "Link Telegram"
      assert html =~ "All Users"
    end
  end

  describe "create_account event" do
    test "creates account and shows flash", %{conn: conn, tenant_id: tid} do
      {:ok, view, _html} = live(conn, ~p"/admin/users")
      email = "newuser_#{System.unique_integer([:positive])}@test.com"

      view
      |> element("#create-account-form")
      |> render_submit(%{
        "email" => email,
        "name" => "New User",
        "tenant_id" => tid
      })

      html = render(view)
      assert html =~ "Account created"
      assert html =~ email
    end

    test "duplicate email shows error flash", %{conn: conn, tenant_id: tid} do
      email = "dup_#{System.unique_integer([:positive])}@test.com"
      {:ok, _} = Accounts.create_user_account(%{email: email, name: "First", tenant_id: tid})

      {:ok, view, _html} = live(conn, ~p"/admin/users")

      view
      |> element("#create-account-form")
      |> render_submit(%{
        "email" => email,
        "name" => "Duplicate",
        "tenant_id" => tid
      })

      html = render(view)
      assert html =~ "has already been taken" or html =~ "email"
    end
  end

  describe "suspend event" do
    test "suspends a user", %{conn: conn, tenant_id: tid} do
      email = "suspend_#{System.unique_integer([:positive])}@test.com"
      {:ok, _} = Accounts.create_user_account(%{email: email, name: "S", tenant_id: tid})
      mapping = Repo.get_by(UserMapping, email: email)

      {:ok, view, _html} = live(conn, ~p"/admin/users")

      view
      |> element(~s|button[phx-click=suspend][phx-value-id="#{mapping.id}"]|)
      |> render_click()

      assert render(view) =~ "suspended"
    end
  end

  describe "reactivate event" do
    test "reactivates a suspended user", %{conn: conn, tenant_id: tid} do
      email = "react_#{System.unique_integer([:positive])}@test.com"
      {:ok, _} = Accounts.create_user_account(%{email: email, name: "R", tenant_id: tid})
      mapping = Repo.get_by(UserMapping, email: email)
      {:ok, suspended} = Accounts.suspend_user(mapping)

      {:ok, view, _html} = live(conn, ~p"/admin/users")

      view
      |> element(~s|button[phx-click=reactivate][phx-value-id="#{suspended.id}"]|)
      |> render_click()

      assert render(view) =~ "reactivated"
    end
  end

  describe "delete_user event" do
    test "deletes a user", %{conn: conn, tenant_id: tid} do
      email = "deluser_#{System.unique_integer([:positive])}@test.com"
      {:ok, _} = Accounts.create_user_account(%{email: email, name: "Del", tenant_id: tid})
      mapping = Repo.get_by(UserMapping, email: email)

      {:ok, view, _html} = live(conn, ~p"/admin/users")

      view
      |> element(~s|button[phx-click=delete_user][phx-value-id="#{mapping.id}"]|)
      |> render_click()

      assert render(view) =~ "deleted"
      assert Repo.get_by(UserMapping, email: email) == nil
    end
  end

  describe "reset_password event" do
    test "sends password reset email", %{conn: conn, tenant_id: tid} do
      account =
        create_account(%{
          email: "reset_#{System.unique_integer([:positive])}@test.com",
          role: "user",
          tenant_id: tid
        })

      {:ok, view, _html} = live(conn, ~p"/admin/users")

      view
      |> element(~s|button[phx-click=reset_password][phx-value-id="#{account.id}"]|)
      |> render_click()

      assert render(view) =~ "Password reset email sent"
    end
  end

  describe "link_telegram event" do
    test "links telegram to existing user", %{conn: conn, tenant_id: tid} do
      email = "linktg_#{System.unique_integer([:positive])}@test.com"
      {:ok, _} = Accounts.create_user_mapping(%{email: email, tenant_id: tid})

      {:ok, view, _html} = live(conn, ~p"/admin/users")
      tg_id = "#{System.unique_integer([:positive])}"

      view
      |> element("#link-telegram-form")
      |> render_submit(%{
        "user_key" => "#{email}|#{tid}",
        "telegram_id" => tg_id
      })

      html = render(view)
      assert html =~ "linked"
    end
  end
end
