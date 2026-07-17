defmodule CrmReactorWeb.AdminController do
  use CrmReactorWeb, :controller

  alias CrmReactor.AI.SubscriptionCache
  alias CrmReactor.GDPR.{AuditLog, DataSubject}
  alias CrmReactor.Repo
  alias CrmReactor.Tenants.Provisioner

  plug :verify_admin_token

  def provision(conn, %{"tenant_id" => tid, "company_name" => name} = params) do
    user_id = params["telegram_chat_id"] || params["user_id"]

    opts = [
      admin_email: params["admin_email"],
      email: params["email"] || params["user_email"] || params["admin_email"],
      telegram_id: params["telegram_chat_id"]
    ]

    case Provisioner.provision(tid, name, user_id, opts) do
      {:ok, tenant} ->
        json(conn, %{
          success: true,
          tenant_id: tenant.tenant_id,
          schema_name: tenant.schema_name
        })

      {:error, :invalid_tenant_id} ->
        conn
        |> put_status(400)
        |> json(%{error: "Invalid tenant_id: must be lowercase alphanumeric with underscores"})

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

  def set_subscription(conn, %{"tenant_id" => tid, "workflow_name" => wf, "enabled" => enabled})
      when is_boolean(enabled) do
    case SubscriptionCache.set(tid, wf, enabled) do
      :ok ->
        json(conn, %{success: true, tenant_id: tid, workflow_name: wf, enabled: enabled})

      {:error, reason} ->
        require Logger
        Logger.error("Subscription update failed: #{inspect(reason)}")
        conn |> put_status(422) |> json(%{error: "Failed to update subscription"})
    end
  end

  def set_subscription(conn, _params) do
    conn
    |> put_status(400)
    |> json(%{error: "tenant_id, workflow_name, and enabled (bool) required"})
  end

  def set_webhook(conn, %{"tenant_id" => tid, "webhook_url" => url}) do
    case Provisioner.set_webhook(tid, url) do
      {:ok, tenant} ->
        json(conn, %{success: true, tenant_id: tid, webhook_url: tenant.webhook_url})

      {:error, :not_found} ->
        conn |> put_status(404) |> json(%{error: "Tenant not found"})
    end
  end

  def set_webhook(conn, _params) do
    conn |> put_status(400) |> json(%{error: "tenant_id and webhook_url required"})
  end

  def get_webhook_secret(conn, %{"tenant_id" => tid}) do
    alias CrmReactor.Tenants.Tenant

    case Repo.get_by(Tenant, tenant_id: tid) do
      nil ->
        conn |> put_status(404) |> json(%{error: "Tenant not found"})

      %{webhook_secret: nil} ->
        conn |> put_status(404) |> json(%{error: "No webhook configured"})

      tenant ->
        json(conn, %{tenant_id: tid, webhook_secret: tenant.webhook_secret})
    end
  end

  def export_subject(conn, %{"identifier" => identifier}) do
    case DataSubject.export(identifier) do
      {:ok, data} ->
        AuditLog.record("export", identifier, "admin_api")
        json(conn, data)

      {:error, :not_found} ->
        conn |> put_status(404) |> json(%{error: "Data subject not found"})
    end
  end

  def email_subject(conn, %{"identifier" => identifier}) do
    case DataSubject.export_and_email(identifier) do
      {:ok, %{email_sent: true}} ->
        AuditLog.record("email_export", identifier, "admin_api")
        json(conn, %{success: true, message: "Export envoyé par email"})

      {:ok, %{email_sent: false}} ->
        conn
        |> put_status(422)
        |> json(%{error: "Aucune adresse email enregistrée pour cet utilisateur"})

      {:error, :not_found} ->
        conn |> put_status(404) |> json(%{error: "Data subject not found"})

      {:error, reason} ->
        require Logger
        Logger.error("Email export failed: #{inspect(reason)}")
        conn |> put_status(500) |> json(%{error: "Internal server error"})
    end
  end

  def erase_subject(conn, %{"identifier" => identifier}) do
    case DataSubject.erase(identifier) do
      {:ok, _} ->
        AuditLog.record("erase", identifier, "admin_api")
        json(conn, %{success: true, erased: identifier})

      {:error, :not_found} ->
        conn |> put_status(404) |> json(%{error: "Data subject not found"})
    end
  end

  def erase_contact(conn, %{"schema" => schema, "contact_id" => contact_id}) do
    with true <- Regex.match?(~r/^[a-z_][a-z0-9_]*$/, schema),
         {id, ""} <- Integer.parse(contact_id) do
      case DataSubject.erase_contact(schema, id) do
        {:ok, _} ->
          AuditLog.record("erase_contact", contact_id, "admin_api", %{schema: schema})
          json(conn, %{success: true, contact_id: contact_id})

        {:error, :not_found} ->
          conn |> put_status(404) |> json(%{error: "Contact not found"})
      end
    else
      _ -> conn |> put_status(400) |> json(%{error: "Invalid schema or contact_id"})
    end
  end

  defp verify_admin_token(conn, _opts) do
    expected = Application.get_env(:crm_reactor, :admin_token)

    case get_req_header(conn, "authorization") do
      ["bearer " <> token] -> secure_check(conn, token, expected)
      ["Bearer " <> token] -> secure_check(conn, token, expected)
      _ -> conn |> put_status(401) |> json(%{error: "Unauthorized"}) |> halt()
    end
  end

  defp secure_check(conn, token, expected) do
    if Plug.Crypto.secure_compare(token, expected) do
      conn
    else
      conn |> put_status(401) |> json(%{error: "Unauthorized"}) |> halt()
    end
  end

  defp format_errors(%Ecto.Changeset{} = cs) do
    Ecto.Changeset.traverse_errors(cs, fn {msg, _opts} -> msg end)
  end

  defp format_errors(other), do: inspect(other)
end
