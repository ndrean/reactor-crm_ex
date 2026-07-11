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

config :crm_reactor, CrmReactor.Mailer, adapter: Swoosh.Adapters.Local
config :swoosh, :api_client, false

config :crm_reactor, Oban,
  repo: CrmReactor.Repo,
  queues: [ingest: 10, mutations: 5, maintenance: 1, webhooks: 3],
  plugins: [
    {Oban.Plugins.Cron,
     crontab: [
       {"0 3 * * *", CrmReactor.Workers.RetentionWorker},
       {"30 3 * * *", CrmReactor.Workers.FileCleanupWorker}
       # Cosine self-learning loop disabled
       # {"0 4 * * 0", CrmReactor.Workers.ThresholdCalibrationWorker},
       # {"30 5 * * *", CrmReactor.Workers.ExampleReviewWorker}
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

config :nx, :default_backend, EXLA.Backend

import_config "#{config_env()}.exs"
