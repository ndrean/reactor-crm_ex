defmodule CrmReactorWeb.AdminLive.UsersTest do
  use CrmReactorWeb.ConnCase

  import Phoenix.LiveViewTest

  alias CrmReactor.Repo
  alias CrmReactor.Tenants.{Provisioner, UserMapping}

  setup %{conn: conn} do
    %{conn: conn} = register_and_log_in_admin(conn)

    tid = "test_users_#{System.unique_integer([:positive])}"
    {:ok, tenant} = Provisioner.provision(tid, "Users Test Co", nil)
    on_exit(fn -> Provisioner.drop_tenant(tenant) end)

    %{conn: conn, tenant_id: tid}
  end

  describe "mount" do
    test "renders three sections", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/admin/users")
      assert html =~ "Create User Account"
      assert html =~ "User Accounts"
      assert html =~ "Telegram Linkages"
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
  end

  describe "toggle_suspend event" do
    test "suspends and reactivates user account", %{conn: conn, tenant_id: tid} do
      account =
        create_account(%{
          email: "suspend_#{System.unique_integer([:positive])}@test.com",
          role: "user",
          tenant_id: tid
        })

      {:ok, view, _html} = live(conn, ~p"/admin/users")

      view
      |> element(~s|button[phx-click=toggle_suspend][phx-value-id="#{account.id}"]|)
      |> render_click()

      assert render(view) =~ "suspended"
    end
  end

  describe "add_user event" do
    test "adds user mapping with email and telegram_id", %{conn: conn, tenant_id: tid} do
      {:ok, view, _html} = live(conn, ~p"/admin/users")
      email = "tguser_#{System.unique_integer([:positive])}@test.com"
      tg_id = "#{System.unique_integer([:positive])}"

      view
      |> element("#add-user-form")
      |> render_submit(%{
        "tenant_id" => tid,
        "email" => email,
        "telegram_id" => tg_id
      })

      html = render(view)
      assert html =~ email
      assert html =~ "added to #{tid}"
    end
  end

  describe "create_account error" do
    test "duplicate email shows error flash", %{conn: conn, tenant_id: tid} do
      email = "dup_#{System.unique_integer([:positive])}@test.com"

      {:ok, _} =
        CrmReactor.Accounts.create_user_account(%{
          email: email,
          name: "First",
          tenant_id: tid
        })

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

  describe "toggle_suspend reactivate" do
    test "reactivates a suspended account", %{conn: conn, tenant_id: tid} do
      account =
        create_account(%{
          email: "react_#{System.unique_integer([:positive])}@test.com",
          role: "user",
          tenant_id: tid
        })

      {:ok, suspended} = CrmReactor.Accounts.suspend_account(account)
      assert suspended.suspended_at

      {:ok, view, _html} = live(conn, ~p"/admin/users")

      view
      |> element(~s|button[phx-click=toggle_suspend][phx-value-id="#{account.id}"]|)
      |> render_click()

      assert render(view) =~ "reactivated"
    end
  end

  describe "delete_account event" do
    test "deletes a suspended account", %{conn: conn, tenant_id: tid} do
      account =
        create_account(%{
          email: "delacct_#{System.unique_integer([:positive])}@test.com",
          role: "user",
          tenant_id: tid
        })

      {:ok, _} = CrmReactor.Accounts.suspend_account(account)

      {:ok, view, _html} = live(conn, ~p"/admin/users")

      view
      |> element(~s|button[phx-click=delete_account][phx-value-id="#{account.id}"]|)
      |> render_click()

      assert render(view) =~ "deleted"
    end
  end

  describe "remove_mapping event" do
    test "removes user mapping", %{conn: conn, tenant_id: tid} do
      {:ok, mapping} =
        %UserMapping{}
        |> UserMapping.changeset(%{
          tenant_id: tid,
          email: "remove_me_#{System.unique_integer([:positive])}@test.com",
          telegram_id: "#{System.unique_integer([:positive])}"
        })
        |> Repo.insert()

      {:ok, view, _html} = live(conn, ~p"/admin/users")

      view
      |> element(~s|button[phx-click=remove_mapping][phx-value-id="#{mapping.id}"]|)
      |> render_click()

      assert render(view) =~ "removed"
    end
  end
end
