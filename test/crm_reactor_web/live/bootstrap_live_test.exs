defmodule CrmReactorWeb.BootstrapLiveTest do
  use CrmReactorWeb.ConnCase

  import Phoenix.LiveViewTest

  alias CrmReactor.Accounts.Account
  alias CrmReactor.Repo

  describe "bootstrap /setup" do
    test "rejects access without bootstrap_token configured", %{conn: conn} do
      Application.put_env(:crm_reactor, :bootstrap_token, nil)

      {:ok, _view, html} = live(conn, "/setup")
      assert html =~ "Bootstrap not configured"
    after
      Application.delete_env(:crm_reactor, :bootstrap_token)
    end

    test "rejects access with wrong token", %{conn: conn} do
      Application.put_env(:crm_reactor, :bootstrap_token, "correct-token")

      {:ok, _view, html} = live(conn, "/setup?token=wrong-token")
      assert html =~ "Invalid token"
    after
      Application.delete_env(:crm_reactor, :bootstrap_token)
    end

    test "rejects when admin already exists", %{conn: conn} do
      Application.put_env(:crm_reactor, :bootstrap_token, "test-token")

      # Create an admin
      %Account{}
      |> Account.registration_changeset(%{
        email: "existing@test.com",
        password: "password1234",
        role: "admin"
      })
      |> Repo.insert!()

      {:ok, _view, html} = live(conn, "/setup?token=test-token")
      assert html =~ "Setup already completed"
    after
      Application.delete_env(:crm_reactor, :bootstrap_token)
    end

    @tag :bootstrap_isolation
    test "shows form and creates admin when no admins exist", %{conn: conn} do
      # This test requires zero admin accounts. It deletes all accounts
      # which can conflict with concurrent tests in the shared sandbox.
      # Run alone if flaky: mix test --only bootstrap_isolation
      Repo.delete_all(CrmReactor.Accounts.AccountToken)
      Repo.delete_all(Account)

      Application.put_env(:crm_reactor, :bootstrap_token, "test-token")

      {:ok, view, html} = live(conn, "/setup?token=test-token")
      assert html =~ "Create Admin Account"
      assert html =~ "Initial Setup"

      assert view
             |> form("#bootstrap-form",
               admin: %{email: "newadmin@test.com", password: "password1234"}
             )
             |> render_submit()

      assert_redirect(view, "/login")
      assert Repo.get_by(Account, email: "newadmin@test.com", role: "admin")
    after
      Application.delete_env(:crm_reactor, :bootstrap_token)
    end
  end
end
