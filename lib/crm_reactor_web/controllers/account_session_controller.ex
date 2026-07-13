defmodule CrmReactorWeb.AccountSessionController do
  use CrmReactorWeb, :controller

  alias CrmReactorWeb.Plugs.AccountAuth

  def root(conn, _params) do
    redirect(conn, to: "/login")
  end

  def create(conn, %{"account" => %{"email" => email, "password" => password}}) do
    if account = CrmReactor.Accounts.get_account_by_email_and_password(email, password) do
      AccountAuth.log_in_account(conn, account)
    else
      conn
      |> put_flash(:error, "Email ou mot de passe invalide.")
      |> redirect(to: "/login")
    end
  end

  def delete(conn, _params) do
    AccountAuth.log_out_account(conn)
  end
end
