defmodule CrmReactorWeb.ConnCase do
  @moduledoc """
  This module defines the test case to be used by
  tests that require setting up a connection.

  Such tests rely on `Phoenix.ConnTest` and also
  import other functionality to make it easier
  to build common data structures and query the data layer.

  Finally, if the test case interacts with the database,
  we enable the SQL sandbox, so changes done to the database
  are reverted at the end of every test. If you are using
  PostgreSQL, you can even run database tests asynchronously
  by setting `use CrmReactorWeb.ConnCase, async: true`, although
  this option is not recommended for other databases.
  """

  use ExUnit.CaseTemplate

  using do
    quote do
      # The default endpoint for testing
      @endpoint CrmReactorWeb.Endpoint

      use CrmReactorWeb, :verified_routes

      # Import conveniences for testing with connections
      import Plug.Conn
      import Phoenix.ConnTest
      import CrmReactorWeb.ConnCase
    end
  end

  setup tags do
    CrmReactor.DataCase.setup_sandbox(tags)
    {:ok, conn: Phoenix.ConnTest.build_conn()}
  end

  @doc "Logs in an account by putting the session token into the connection."
  def log_in_account(conn, account) do
    token = CrmReactor.Accounts.generate_account_session_token(account)

    conn
    |> Phoenix.ConnTest.init_test_session(%{})
    |> Plug.Conn.put_session(:account_token, token)
  end

  alias CrmReactor.Accounts.Account
  alias CrmReactor.Repo

  @doc "Creates a user account for testing (no password — already confirmed)."
  def register_and_log_in_user(conn, attrs \\ %{}) do
    tenant_id = attrs[:tenant_id] || "test_tenant"
    email = attrs[:email] || "user_#{System.unique_integer([:positive])}@test.com"

    role = attrs[:role] || "user"

    {:ok, account} =
      %Account{}
      |> Account.registration_changeset(%{
        email: email,
        password: "password1234",
        role: role,
        tenant_id: tenant_id
      })
      |> Repo.insert()

    # Force confirm
    account
    |> Ecto.Changeset.change(%{confirmed_at: DateTime.utc_now() |> DateTime.truncate(:second)})
    |> Repo.update!()

    account = Repo.get!(Account, account.id)

    conn = log_in_account(conn, account)
    %{conn: conn, account: account}
  end

  @doc "Creates an admin account for testing (confirmed, role=admin)."
  def register_and_log_in_admin(conn, attrs \\ %{}) do
    register_and_log_in_user(conn, Map.merge(%{role: "admin"}, attrs))
  end

  @doc "Creates a confirmed account without logging in."
  def create_account(attrs \\ %{}) do
    tenant_id = attrs[:tenant_id] || "test_tenant"
    email = attrs[:email] || "user_#{System.unique_integer([:positive])}@test.com"
    role = attrs[:role] || "user"

    {:ok, account} =
      %Account{}
      |> Account.registration_changeset(%{
        email: email,
        password: attrs[:password] || "password1234",
        role: role,
        tenant_id: tenant_id
      })
      |> Repo.insert()

    account
    |> Ecto.Changeset.change(%{confirmed_at: DateTime.utc_now() |> DateTime.truncate(:second)})
    |> Repo.update!()

    Repo.get!(Account, account.id)
  end
end
