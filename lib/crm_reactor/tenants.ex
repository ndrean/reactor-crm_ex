defmodule CrmReactor.Tenants do
  @moduledoc "Public API for tenant lookups shared across web and pipeline."

  alias CrmReactor.Tenants.TenantCache

  @doc "Resolves the active tenant schema name for a given user identifier."
  def schema_for_user(user_id) do
    case TenantCache.lookup(user_id) do
      {:ok, %{schema_name: schema}} -> {:ok, schema}
      {:error, :unknown_user} = err -> err
    end
  end
end
