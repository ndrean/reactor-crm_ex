defmodule CrmReactorWeb.AdminController do
  use CrmReactorWeb, :controller

  alias CrmReactor.GDPR.DataSubject
  alias CrmReactor.Tenants.Provisioner

  plug :verify_admin_token

  def provision(conn, %{"tenant_id" => tid, "company_name" => name} = params) do
    user_id = params["telegram_chat_id"] || params["user_id"]

    opts = [
      admin_email: params["admin_email"],
      user_email: params["user_email"]
    ]

    case Provisioner.provision(tid, name, user_id, opts) do
      {:ok, tenant} ->
        json(conn, %{
          success: true,
          tenant_id: tenant.tenant_id,
          schema_name: tenant.schema_name
        })

      {:error, changeset} ->
        conn |> put_status(422) |> json(%{error: format_errors(changeset)})
    end
  end

  def toggle(conn, %{"tenant_id" => tid, "active" => active}) do
    case Provisioner.toggle_active(tid, active) do
      {:ok, tenant} ->
        json(conn, %{success: true, is_active: tenant.is_active})

      {:error, :not_found} ->
        conn |> put_status(404) |> json(%{error: "Tenant not found"})
    end
  end

  def export_subject(conn, %{"identifier" => identifier}) do
    case DataSubject.export(identifier) do
      {:ok, data} ->
        json(conn, data)

      {:error, :not_found} ->
        conn |> put_status(404) |> json(%{error: "Data subject not found"})
    end
  end

  def email_subject(conn, %{"identifier" => identifier}) do
    case DataSubject.export_and_email(identifier) do
      {:ok, %{email_sent: true}} ->
        json(conn, %{success: true, message: "Export envoyé par email"})

      {:ok, %{email_sent: false}} ->
        conn
        |> put_status(422)
        |> json(%{error: "Aucune adresse email enregistrée pour cet utilisateur"})

      {:error, :not_found} ->
        conn |> put_status(404) |> json(%{error: "Data subject not found"})

      {:error, reason} ->
        conn |> put_status(500) |> json(%{error: inspect(reason)})
    end
  end

  def erase_subject(conn, %{"identifier" => identifier}) do
    case DataSubject.erase(identifier) do
      {:ok, _} ->
        json(conn, %{success: true, erased: identifier})

      {:error, :not_found} ->
        conn |> put_status(404) |> json(%{error: "Data subject not found"})
    end
  end

  def erase_contact(conn, %{"schema" => schema, "contact_id" => contact_id}) do
    case DataSubject.erase_contact(schema, String.to_integer(contact_id)) do
      {:ok, _} ->
        json(conn, %{success: true, contact_id: contact_id})

      {:error, :not_found} ->
        conn |> put_status(404) |> json(%{error: "Contact not found"})
    end
  end

  defp verify_admin_token(conn, _opts) do
    expected = Application.get_env(:crm_reactor, :admin_token)

    case get_req_header(conn, "authorization") do
      ["bearer " <> token] when token == expected -> conn
      ["Bearer " <> token] when token == expected -> conn
      _ -> conn |> put_status(401) |> json(%{error: "Unauthorized"}) |> halt()
    end
  end

  defp format_errors(%Ecto.Changeset{} = cs) do
    Ecto.Changeset.traverse_errors(cs, fn {msg, _opts} -> msg end)
  end

  defp format_errors(other), do: inspect(other)
end
