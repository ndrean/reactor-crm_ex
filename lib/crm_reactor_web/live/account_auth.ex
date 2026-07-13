defmodule CrmReactorWeb.AccountAuth do
  @moduledoc "LiveView on_mount hooks for account-based authentication."

  import Phoenix.LiveView
  import Phoenix.Component, only: [assign: 3]

  alias CrmReactor.Accounts

  def on_mount(:ensure_authenticated, _params, session, socket) do
    case mount_account(session, socket) do
      {:ok, socket} -> {:cont, socket}
      :error -> {:halt, redirect(socket, to: "/login")}
    end
  end

  def on_mount(:ensure_admin, _params, session, socket) do
    case mount_account(session, socket) do
      {:ok, %{assigns: %{current_account: %{role: "admin"}}} = socket} ->
        {:cont, socket}

      _ ->
        {:halt, redirect(socket, to: "/login")}
    end
  end

  def on_mount(:ensure_user, _params, session, socket) do
    case mount_account(session, socket) do
      {:ok,
       %{
         assigns: %{
           current_account: %{role: "user", confirmed_at: confirmed, suspended_at: suspended}
         }
       } = socket}
      when not is_nil(confirmed) and is_nil(suspended) ->
        {:cont, socket}

      _ ->
        {:halt, redirect(socket, to: "/login")}
    end
  end

  def on_mount(:redirect_if_authenticated, _params, session, socket) do
    case mount_account(session, socket) do
      {:ok, %{assigns: %{current_account: %{role: "admin"}}} = socket} ->
        {:halt, redirect(socket, to: "/admin")}

      {:ok, socket} ->
        {:halt, redirect(socket, to: "/chat")}

      :error ->
        {:cont, assign(socket, :current_account, nil)}
    end
  end

  defp mount_account(session, socket) do
    Phoenix.Component.assign_new(socket, :current_account, fn ->
      if token = session["account_token"] do
        Accounts.get_account_by_session_token(token)
      end
    end)
    |> case do
      %{assigns: %{current_account: %Accounts.Account{}}} = socket -> {:ok, socket}
      _ -> :error
    end
  end
end
