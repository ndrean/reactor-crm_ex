defmodule CrmReactor.Tenants do
  @moduledoc "Public API for tenant lookups shared across web and pipeline."

  import Ecto.Query

  alias CrmReactor.Repo
  alias CrmReactor.Tenants.{Tenant, UserMapping}

  @doc "Resolves the active tenant schema name for a given user identifier."
  def schema_for_user(user_id) do
    query =
      from m in UserMapping,
        join: t in Tenant,
        on: t.tenant_id == m.tenant_id,
        where: m.user_identifier == ^user_id and t.is_active == true,
        select: t.schema_name

    case Repo.one(query) do
      nil -> {:error, :unknown_user}
      schema -> {:ok, schema}
    end
  end
end
