defmodule CrmReactor.GDPR.DataSubject do
  @moduledoc """
  GDPR data subject rights: right to erasure (Art. 17),
  right of access and data portability (Art. 15, 20).
  """

  alias CrmReactor.CRM.{Contact, ExecutionLog}
  alias CrmReactor.Emails.GdprExportEmail
  alias CrmReactor.Mailer
  alias CrmReactor.Repo
  alias CrmReactor.Tenants.{Tenant, UserMapping}

  import CrmReactor.QueryHelpers, only: [ilike_pattern: 1]
  import Ecto.Query

  @redacted "[REDACTED]"

  @doc """
  Export all data held about a data subject identified by user_identifier.
  Returns a map suitable for JSON serialization.
  """
  def export(user_identifier) do
    case resolve(user_identifier) do
      nil -> {:error, :not_found}
      {tenant, schema, _user_email} -> {:ok, build_export(user_identifier, tenant, schema)}
    end
  end

  @doc """
  Export personal data and send it by email to the user's registered address.
  Returns {:ok, %{..., email_sent: true/false}} or {:error, reason}.
  """
  def export_and_email(user_identifier) do
    case resolve(user_identifier) do
      nil ->
        {:error, :not_found}

      {tenant, schema, nil} ->
        {:ok, Map.put(build_export(user_identifier, tenant, schema), :email_sent, false)}

      {tenant, schema, user_email} ->
        data = build_export(user_identifier, tenant, schema)

        case GdprExportEmail.build(user_email, data) |> Mailer.deliver() do
          {:ok, _} -> {:ok, Map.put(data, :email_sent, true)}
          {:error, reason} -> {:error, {:email_delivery_failed, reason}}
        end
    end
  end

  @doc """
  Erase all personal data for a data subject.
  - Redacts raw_input and output in execution_logs
  - Removes user_mapping entry
  Does NOT delete the tenant or other users' data.
  """
  def erase(user_identifier) do
    case resolve(user_identifier) do
      nil ->
        {:error, :not_found}

      {_tenant, schema, _user_email} ->
        Repo.transaction(fn ->
          redact_execution_logs(schema, user_identifier)
          remove_user_mapping(user_identifier)
        end)
    end
  end

  @doc """
  Erase a specific contact by ID within a tenant schema,
  and redact their name from execution_logs.
  """
  def erase_contact(schema, contact_id) do
    case Repo.get(Contact, contact_id, prefix: schema) do
      nil ->
        {:error, :not_found}

      contact ->
        name_pattern = ilike_pattern(contact.first_name)

        Repo.transaction(fn ->
          Repo.delete!(contact, prefix: schema)
          redact_logs_by_pattern(schema, name_pattern)
        end)
    end
  end

  defp resolve(identifier) do
    query =
      from m in UserMapping,
        join: t in Tenant,
        on: t.tenant_id == m.tenant_id,
        where: m.email == ^identifier or m.telegram_id == ^identifier,
        select: {t, t.schema_name, m.email}

    Repo.one(query)
  end

  defp build_export(user_identifier, tenant, schema) do
    contacts = Repo.all(Contact, prefix: schema)

    logs =
      from(l in ExecutionLog,
        where: l.triggered_by == ^user_identifier,
        order_by: [desc: l.logged_at]
      )
      |> Repo.all(prefix: schema)

    %{
      tenant: %{
        tenant_id: tenant.tenant_id,
        company_name: tenant.company_name,
        created_at: tenant.inserted_at
      },
      user_identifier: user_identifier,
      contacts: Enum.map(contacts, &contact_to_map/1),
      execution_logs:
        Enum.map(logs, fn l ->
          %{
            id: l.id,
            raw_input: l.raw_input,
            action: l.action,
            output: l.output,
            status: l.status,
            logged_at: l.logged_at,
            completed_at: l.completed_at
          }
        end),
      exported_at: DateTime.utc_now() |> DateTime.truncate(:second)
    }
  end

  defp redact_execution_logs(schema, user_identifier) do
    from(l in ExecutionLog, where: l.triggered_by == ^user_identifier)
    |> Repo.update_all(
      [
        set: [
          raw_input: @redacted,
          output: @redacted,
          error_message: @redacted,
          status: "erased"
        ]
      ],
      prefix: schema
    )
  end

  defp redact_logs_by_pattern(schema, pattern) do
    from(l in ExecutionLog,
      where: ilike(l.raw_input, ^pattern) or ilike(l.output, ^pattern)
    )
    |> Repo.update_all(
      [
        set: [
          raw_input: @redacted,
          output: @redacted
        ]
      ],
      prefix: schema
    )
  end

  defp remove_user_mapping(identifier) do
    from(m in UserMapping, where: m.email == ^identifier or m.telegram_id == ^identifier)
    |> Repo.delete_all()
  end

  defp contact_to_map(c) do
    %{
      id: c.id,
      first_name: c.first_name,
      last_name: c.last_name,
      email: c.email,
      phone: c.phone,
      company_name: c.company_name,
      created_at: c.created_at
    }
  end
end
