defmodule CrmReactor.Reactors.Steps.ResolveTenant do
  @moduledoc "Reactor step: resolve user identifier to active tenant schema."
  use Reactor.Step

  alias CrmReactor.Repo
  alias CrmReactor.Tenants.{Tenant, UserMapping}
  import Ecto.Query

  @impl true
  def run(%{user_id: user_id}, _context, _options) do
    query =
      from m in UserMapping,
        join: t in Tenant,
        on: t.tenant_id == m.tenant_id,
        where: m.user_identifier == ^user_id and t.is_active == true,
        select: %{
          tenant_id: t.tenant_id,
          schema_name: t.schema_name,
          company_name: t.company_name,
          admin_email: t.admin_email
        }

    case Repo.one(query) do
      nil -> {:error, :unknown_user}
      tenant -> {:ok, tenant}
    end
  end
end
