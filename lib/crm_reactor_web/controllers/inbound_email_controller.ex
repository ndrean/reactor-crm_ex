defmodule CrmReactorWeb.InboundEmailController do
  use CrmReactorWeb, :controller

  alias CrmReactor.Emails.IncomingEmail
  alias CrmReactor.Repo

  def create(conn, params) do
    expected = Application.get_env(:crm_reactor, :email_webhook_secret)

    case get_req_header(conn, "x-email-secret") do
      [secret] when is_binary(secret) and is_binary(expected) ->
        if Plug.Crypto.secure_compare(secret, expected) do
          handle_email(conn, params)
        else
          conn |> put_status(401) |> json(%{error: "Invalid secret"})
        end

      _ ->
        conn |> put_status(401) |> json(%{error: "Invalid secret"})
    end
  end

  defp handle_email(conn, %{"from" => from} = params) when is_binary(from) do
    attrs = %{
      from_address: from,
      subject: params["subject"],
      body_text: params["body"],
      received_at: DateTime.utc_now() |> DateTime.truncate(:second)
    }

    case %IncomingEmail{} |> IncomingEmail.changeset(attrs) |> Repo.insert() do
      {:ok, _email} -> json(conn, %{ok: true})
      {:error, _changeset} -> conn |> put_status(422) |> json(%{error: "Invalid data"})
    end
  end

  defp handle_email(conn, _params) do
    conn |> put_status(400) |> json(%{error: "Missing required field: from"})
  end
end
