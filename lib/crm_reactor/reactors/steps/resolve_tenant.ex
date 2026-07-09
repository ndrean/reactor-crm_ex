defmodule CrmReactor.Reactors.Steps.ResolveTenant do
  @moduledoc "Reactor step: resolve user identifier to active tenant schema."
  use Reactor.Step

  alias CrmReactor.Tenants.TenantCache

  @impl true
  def run(%{user_id: user_id}, _context, _options) do
    TenantCache.lookup(user_id)
  end
end
