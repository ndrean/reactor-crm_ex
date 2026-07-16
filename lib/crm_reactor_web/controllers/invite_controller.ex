defmodule CrmReactorWeb.InviteController do
  use CrmReactorWeb, :controller

  alias CrmReactor.Accounts
  alias CrmReactor.Accounts.AccountToken
  alias CrmReactor.Repo
  alias CrmReactorWeb.Plugs.AccountAuth

  def show(conn, %{"token" => token}) do
    case AccountToken.verify_invite_token_query(token) do
      {:ok, query} ->
        if Repo.one(query) do
          render(conn, :show, token: token, error: nil, layout: false)
        else
          conn
          |> put_flash(:error, "Le lien d'invitation est invalide ou a expiré.")
          |> redirect(to: "/login")
        end

      :error ->
        conn
        |> put_flash(:error, "Le lien d'invitation est invalide.")
        |> redirect(to: "/login")
    end
  end

  def accept(conn, %{"token" => token, "password" => password}) do
    case Accounts.accept_invite(token, password) do
      {:ok, account} ->
        AccountAuth.log_in_account(conn, account)

      {:error, _reason} ->
        conn
        |> put_flash(:error, "Le lien d'invitation est invalide ou a expiré.")
        |> redirect(to: "/login")
    end
  end
end
