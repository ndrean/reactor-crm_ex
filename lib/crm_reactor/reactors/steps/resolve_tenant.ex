defmodule CrmReactor.Reactors.Steps.ResolveTenant do
  @moduledoc "Reactor step: resolve user identifier to active tenant schema."
  use Reactor.Step

  alias CrmReactor.Tenants.TenantCache

  @impl true
  def run(%{tenant_override: tenant}, _context, _options) when is_map(tenant) do
    {:ok, tenant}
  end

  def run(%{user_id: user_id}, _context, _options) do
    TenantCache.lookup(user_id)
  end
end
