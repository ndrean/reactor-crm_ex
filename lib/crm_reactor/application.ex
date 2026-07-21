defmodule CrmReactor.Application do
  @moduledoc false

  use Application

  require Logger

  @impl true
  def start(_type, _args) do
    if Application.get_env(:crm_reactor, CrmReactorWeb.Endpoint)[:server] &&
         is_nil(System.get_env("PHX_HOST")) do
      Logger.warning("PHX_HOST is not set — external URLs will use 'localhost'")
    end

    children = [
      CrmReactor.PromEx,
      CrmReactorWeb.Telemetry,
      CrmReactor.Repo,
      CrmReactor.Vault,
      {Finch,
       name: CrmReactor.Finch,
       pools: %{
         "https://api.mistral.ai" => [size: 50, count: 1],
         :default => [size: 10]
       }},
      CrmReactor.Tenants.TenantCache,
      CrmReactor.AI.RegistryCache,
      CrmReactor.AI.SubscriptionCache,
      CrmReactor.AI.ConversationCache,
      {DNSCluster, query: Application.get_env(:crm_reactor, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: CrmReactor.PubSub},
      {Oban, Application.fetch_env!(:crm_reactor, Oban)},
      CrmReactorWeb.Endpoint
    ]

    opts = [strategy: :one_for_one, name: CrmReactor.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # coveralls-ignore-start
  @impl true
  def config_change(changed, _new, removed) do
    CrmReactorWeb.Endpoint.config_change(changed, removed)
    :ok
  end

  # coveralls-ignore-stop
end
