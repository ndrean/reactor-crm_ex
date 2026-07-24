import Config

# Configure your database
#
# The MIX_TEST_PARTITION environment variable can be used
# to provide built-in test partitioning in CI environment.
# Run `mix help test` for more information.
config :crm_reactor, CrmReactor.Repo,
  username: "postgres_admin",
  password: System.get_env("POSTGRES_PASSWORD", "change-me"),
  hostname: "localhost",
  database: "crm_reactor_test#{System.get_env("MIX_TEST_PARTITION")}",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: System.schedulers_online() * 2

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :crm_reactor, CrmReactorWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "jjfwSigkU2w/AL0zRXu1yp2UTRvPnLXijXTgIddFWDaWmdDbZ1ZkJlQWVbRLDxeu",
  server: false

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

config :crm_reactor, Oban, testing: :manual

config :crm_reactor, CrmReactor.Mailer, adapter: Swoosh.Adapters.Test

config :swoosh, :api_client, false

config :crm_reactor,
  classifier: CrmReactor.AI.MockClassifier,
  admin_token: "dev-admin-token",
  email_webhook_secret: "test-email-secret"

config :bcrypt_elixir, log_rounds: 1

config :crm_reactor, CrmReactor.PromEx, disabled: true

config :crm_reactor, enable_cache_listener: false

config :crm_reactor, file_storage: CrmReactor.MockStorage
