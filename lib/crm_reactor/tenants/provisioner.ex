defmodule CrmReactor.Tenants.Provisioner do
  @moduledoc "Creates and tears down tenant schemas with isolated tables."
  import Ecto.Query

  alias CrmReactor.Repo
  alias CrmReactor.Tenants.{Tenant, TenantCache, UserMapping}

  def provision(tenant_id, company_name, user_identifier \\ nil, opts \\ []) do
    unless Regex.match?(~r/^[a-z0-9_]+$/, tenant_id) do
      {:error, :invalid_tenant_id}
    else
      do_provision(tenant_id, company_name, user_identifier, opts)
    end
  end

  defp do_provision(tenant_id, company_name, user_identifier, opts) do
    schema_name = "customer_#{tenant_id}"
    admin_email = Keyword.get(opts, :admin_email)
    user_email = Keyword.get(opts, :user_email)

    Repo.transaction(fn ->
      tenant =
        case %Tenant{}
             |> Tenant.changeset(%{
               tenant_id: tenant_id,
               company_name: company_name,
               admin_email: admin_email
             })
             |> Repo.insert() do
          {:ok, tenant} -> tenant
          {:error, changeset} -> Repo.rollback(changeset)
        end

      create_tenant_schema(schema_name)

      if user_identifier do
        case %UserMapping{}
             |> UserMapping.changeset(%{
               user_identifier: user_identifier,
               tenant_id: tenant_id,
               user_email: user_email
             })
             |> Repo.insert() do
          {:ok, _mapping} -> :ok
          {:error, changeset} -> Repo.rollback(changeset)
        end
      end

      tenant
    end)
    |> tap(fn
      {:ok, _} -> TenantCache.reload()
      _ -> :ok
    end)
  end

  def drop_tenant(%Tenant{tenant_id: tid, schema_name: schema_name}) do
    Repo.transaction(fn ->
      Repo.query!("DROP SCHEMA IF EXISTS #{safe_schema(schema_name)} CASCADE")
      Repo.delete_all(from m in UserMapping, where: m.tenant_id == ^tid)
      Repo.delete_all(from t in Tenant, where: t.tenant_id == ^tid)
    end)
    |> tap(fn
      {:ok, _} -> TenantCache.reload()
      _ -> :ok
    end)
  end

  def set_webhook(tenant_id, url) do
    case Repo.get_by(Tenant, tenant_id: tenant_id) do
      nil ->
        {:error, :not_found}

      tenant ->
        secret = tenant.webhook_secret || generate_webhook_secret()

        tenant
        |> Ecto.Changeset.change(webhook_url: url, webhook_secret: secret)
        |> Repo.update()
        |> tap(fn
          {:ok, _} -> TenantCache.reload()
          _ -> :ok
        end)
    end
  end

  defp generate_webhook_secret do
    :crypto.strong_rand_bytes(32) |> Base.encode16(case: :lower)
  end

  def toggle_active(tenant_id, active?) do
    case Repo.get_by(Tenant, tenant_id: tenant_id) do
      nil ->
        {:error, :not_found}

      tenant ->
        tenant
        |> Ecto.Changeset.change(is_active: active?)
        |> Repo.update()
        |> tap(fn
          {:ok, _} -> TenantCache.reload()
          _ -> :ok
        end)
    end
  end

  defp create_tenant_schema(schema_name) do
    name = safe_schema(schema_name)
    Repo.query!("CREATE SCHEMA IF NOT EXISTS #{name}")

    Repo.query!("""
    CREATE TABLE IF NOT EXISTS #{name}.contacts (
      id BIGSERIAL PRIMARY KEY,
      first_name TEXT NOT NULL,
      last_name TEXT,
      email BYTEA,
      email_hash BYTEA,
      phone BYTEA,
      phone_hash BYTEA,
      company_name TEXT,
      created_at TIMESTAMPTZ DEFAULT NOW()
    )
    """)

    Repo.query!("""
    CREATE TABLE IF NOT EXISTS #{name}.todos (
      id BIGSERIAL PRIMARY KEY,
      subject TEXT NOT NULL,
      due_date DATE,
      created_by TEXT,
      done BOOLEAN DEFAULT FALSE,
      start_date DATE,
      contact_id BIGINT REFERENCES #{name}.contacts(id) ON DELETE SET NULL,
      starts_at TIMESTAMPTZ,
      ends_at TIMESTAMPTZ,
      location TEXT,
      reminder_minutes INTEGER DEFAULT 30,
      reminder_job_id BIGINT,
      created_at TIMESTAMPTZ DEFAULT NOW()
    )
    """)

    Repo.query!("""
    CREATE TABLE IF NOT EXISTS #{name}.expenses (
      id BIGSERIAL PRIMARY KEY,
      amount DECIMAL(10,2) NOT NULL,
      currency TEXT DEFAULT 'EUR',
      expense_date DATE NOT NULL,
      category TEXT,
      description TEXT,
      created_by TEXT NOT NULL,
      contact_id BIGINT REFERENCES #{name}.contacts(id) ON DELETE SET NULL,
      status TEXT DEFAULT 'pending',
      attachment_key TEXT,
      created_at TIMESTAMPTZ DEFAULT NOW()
    )
    """)

    Repo.query!("""
    CREATE TABLE IF NOT EXISTS #{name}.execution_logs (
      id BIGSERIAL PRIMARY KEY,
      triggered_by TEXT,
      channel TEXT,
      raw_input TEXT,
      action TEXT,
      routing_path TEXT,
      module TEXT,
      status TEXT DEFAULT 'processing',
      proposed_params JSONB,
      pending_id UUID,
      prompt_tokens INTEGER,
      completion_tokens INTEGER,
      total_tokens INTEGER,
      output TEXT,
      error_message TEXT,
      generated_sql TEXT,
      job_id TEXT,
      logged_at TIMESTAMPTZ DEFAULT NOW(),
      completed_at TIMESTAMPTZ,
      CONSTRAINT execution_logs_job_id_unique UNIQUE (job_id)
    )
    """)

    Repo.query!("""
    CREATE TABLE IF NOT EXISTS #{name}.execution_attachments (
      id BIGSERIAL PRIMARY KEY,
      execution_log_id BIGINT REFERENCES #{name}.execution_logs(id) ON DELETE CASCADE,
      filename TEXT NOT NULL,
      content_type TEXT,
      size_bytes INTEGER NOT NULL,
      storage_key TEXT NOT NULL,
      created_at TIMESTAMPTZ DEFAULT NOW()
    )
    """)
  end

  defp safe_schema(name) do
    unless Regex.match?(~r/^[a-z_][a-z0-9_]*$/, name) do
      raise ArgumentError, "invalid schema name: #{name}"
    end

    name
  end
end
