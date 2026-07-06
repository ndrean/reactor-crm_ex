defmodule CrmReactor.PromEx do
  @moduledoc "PromEx metrics configuration for BEAM, Phoenix, Ecto, and Oban."
  use PromEx, otp_app: :crm_reactor

  alias PromEx.Plugins

  @impl true
  def plugins do
    [
      Plugins.Application,
      Plugins.Beam,
      {Plugins.Phoenix, router: CrmReactorWeb.Router, endpoint: CrmReactorWeb.Endpoint},
      Plugins.Ecto,
      Plugins.Oban,
      CrmReactor.PromEx.AIPlugin
    ]
  end

  @impl true
  def dashboard_assigns do
    [
      datasource_id: "prometheus",
      default_selected_interval: "30s"
    ]
  end

  @impl true
  def dashboards do
    [
      {:prom_ex, "application.json"},
      {:prom_ex, "beam.json"},
      {:prom_ex, "phoenix.json"},
      {:prom_ex, "ecto.json"},
      {:prom_ex, "oban.json"}
    ]
  end
end
