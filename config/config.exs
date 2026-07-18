import Config

config :mime, :types, %{
  "text/vcard" => ["vcf"]
}

config :crm_reactor,
  ecto_repos: [CrmReactor.Repo],
  generators: [timestamp_type: :utc_datetime],
  workflow_modules: %{
    "contacts" => CrmReactor.Reactors.Modules.Contacts,
    "todos" => CrmReactor.Reactors.Modules.Todos,
    "expenses" => CrmReactor.Reactors.Modules.Expenses,
    "data" => CrmReactor.Reactors.Modules.DataExport,
    "help" => CrmReactor.Reactors.Modules.Help
  }

config :crm_reactor, CrmReactorWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [json: CrmReactorWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: CrmReactor.PubSub,
  live_view: [signing_salt: "AFyCCQPH"]

config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

config :phoenix, :json_library, Jason
config :phoenix, :filter_parameters, ["password", "secret", "token", "hashed_password", "api_key"]

config :crm_reactor, CrmReactor.Mailer, adapter: Swoosh.Adapters.Local
config :swoosh, :api_client, false

config :crm_reactor, Oban,
  repo: CrmReactor.Repo,
  queues: [ingest: 50, mutations: 10, maintenance: 1, webhooks: 5],
  plugins: [
    {Oban.Plugins.Cron,
     crontab: [
       {"0 3 * * *", CrmReactor.Workers.RetentionWorker},
       {"30 3 * * *", CrmReactor.Workers.FileCleanupWorker}
     ]}
  ]

config :hammer,
  backend: {Hammer.Backend.ETS, [expiry_ms: 60_000 * 10, cleanup_interval_ms: 60_000]}

config :crm_reactor, CrmReactor.PromEx,
  disabled: false,
  manual_metrics_start_delay: :no_delay,
  drop_metrics_groups: [],
  grafana: :disabled,
  metrics_server: :disabled

import_config "#{config_env()}.exs"
