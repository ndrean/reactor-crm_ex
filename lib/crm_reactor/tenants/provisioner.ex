defmodule CrmReactor.Tenants.Provisioner do
  @moduledoc "Creates and tears down tenant schemas with isolated tables."
  import Ecto.Query

  alias CrmReactor.Repo
  alias CrmReactor.Tenants.{Tenant, UserMapping}

  def provision(tenant_id, company_name, user_identifier \\ nil, opts \\ []) do
    schema_name = "customer_#{tenant_id}"
    admin_email = Keyword.get(opts, :admin_email)
    user_email = Keyword.get(opts, :user_email)

    Repo.transaction(fn ->
      tenant =
        %Tenant{}
        |> Tenant.changeset(%{
          tenant_id: tenant_id,
          company_name: company_name,
          admin_email: admin_email
        })
        |> Repo.insert!()

      create_tenant_schema(schema_name)

      if user_identifier do
        %UserMapping{}
        |> UserMapping.changeset(%{
          user_identifier: user_identifier,
          tenant_id: tenant_id,
          user_email: user_email
        })
        |> Repo.insert!()
      end

      tenant
    end)
  end

  def drop_tenant(%Tenant{tenant_id: tid, schema_name: schema_name}) do
    Repo.transaction(fn ->
      Repo.query!("DROP SCHEMA IF EXISTS #{safe_schema(schema_name)} CASCADE")
      Repo.delete_all(from m in UserMapping, where: m.tenant_id == ^tid)
      Repo.delete_all(from t in Tenant, where: t.tenant_id == ^tid)
    end)
  end

  def toggle_active(tenant_id, active?) do
    case Repo.get_by(Tenant, tenant_id: tenant_id) do
      nil -> {:error, :not_found}
      tenant -> tenant |> Ecto.Changeset.change(is_active: active?) |> Repo.update()
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
