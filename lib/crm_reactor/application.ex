defmodule CrmReactor.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      CrmReactor.PromEx,
      CrmReactorWeb.Telemetry,
      CrmReactor.Repo,
      CrmReactor.Vault,
      CrmReactor.Tenants.TenantCache,
      CrmReactor.AI.RegistryCache,
      CrmReactor.AI.SubscriptionCache,
      CrmReactor.AI.ExamplesCache,
      CrmReactor.AI.ThresholdCache,
      {DNSCluster, query: Application.get_env(:crm_reactor, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: CrmReactor.PubSub},
      {Oban, Application.fetch_env!(:crm_reactor, Oban)},
      CrmReactorWeb.Endpoint
    ]

    CrmReactor.AI.ConversationCache.create_table()

    opts = [strategy: :one_for_one, name: CrmReactor.Supervisor]
    result = Supervisor.start_link(children, opts)
    CrmReactor.AI.Similarity.warmup()
    result
  end

  # coveralls-ignore-start
  @impl true
  def config_change(changed, _new, removed) do
    CrmReactorWeb.Endpoint.config_change(changed, removed)
    :ok
  end

  # coveralls-ignore-stop
end
