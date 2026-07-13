defmodule CrmReactorWeb.Plugs.AccountAuth do
  @moduledoc "Plug-based authentication for account sessions."

  import Plug.Conn
  import Phoenix.Controller

  alias CrmReactor.Accounts

  def init(opts), do: opts

  def fetch_current_account(conn, _opts) do
    {account_token, conn} = ensure_account_token(conn)
    account = account_token && Accounts.get_account_by_session_token(account_token)
    assign(conn, :current_account, account)
  end

  def require_authenticated_account(conn, _opts) do
    if conn.assigns[:current_account] do
      conn
    else
      conn
      |> redirect(to: "/login")
      |> halt()
    end
  end

  def require_admin(conn, _opts) do
    if conn.assigns[:current_account] && conn.assigns.current_account.role == "admin" do
      conn
    else
      conn
      |> redirect(to: "/login")
      |> halt()
    end
  end

  def redirect_if_authenticated(conn, _opts) do
    if conn.assigns[:current_account] do
      redirect_by_role(conn, conn.assigns.current_account)
    else
      conn
    end
  end

  def log_in_account(conn, account) do
    token = Accounts.generate_account_session_token(account)

    conn
    |> renew_session()
    |> put_session(:account_token, token)
    |> redirect_by_role(account)
  end

  def log_out_account(conn) do
    account_token = get_session(conn, :account_token)
    account_token && Accounts.delete_account_session_token(account_token)

    conn
    |> renew_session()
    |> redirect(to: "/login")
  end

  defp ensure_account_token(conn) do
    if token = get_session(conn, :account_token) do
      {token, conn}
    else
      {nil, conn}
    end
  end

  defp renew_session(conn) do
    clear_csrf_token()

    conn
    |> configure_session(renew: true)
    |> clear_session()
  end

  defp redirect_by_role(conn, %{role: "admin"}) do
    conn |> redirect(to: "/admin") |> halt()
  end

  defp redirect_by_role(conn, _account) do
    conn |> redirect(to: "/chat") |> halt()
  end

  defp clear_csrf_token do
    Process.delete(:plug_unmasked_csrf_token)
    Process.delete(:plug_masked_csrf_token)
  end
end
