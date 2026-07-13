defmodule CrmReactorWeb.InviteController do
  use CrmReactorWeb, :controller

  alias CrmReactor.Accounts
  alias CrmReactorWeb.Plugs.AccountAuth

  def show(conn, %{"token" => token}) do
    case CrmReactor.Accounts.AccountToken.verify_invite_token_query(token) do
      {:ok, query} ->
        if CrmReactor.Repo.one(query) do
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
