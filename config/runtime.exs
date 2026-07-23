import Config

# Read Docker secrets from /run/secrets/{name} if available, else fall back to env var.
# This supports both Docker Swarm (secrets mounted as files) and dev/CI (env vars).
read_secret = fn name, env_var, default ->
  secret_path = "/run/secrets/#{name}"

  case File.read(secret_path) do
    {:ok, value} -> String.trim(value)
    {:error, _} -> System.get_env(env_var, default)
  end
end

telegram_bot_token = read_secret.("telegram_bot_token", "TELEGRAM_BOT_TOKEN", nil)

config :crm_reactor,
  mistral_api_key: read_secret.("mistral_api_key", "MISTRAL_API_KEY", nil),
  mistral_model_small: System.get_env("MISTRAL_MODEL_SMALL", "mistral-small-latest"),
  mistral_model_large: System.get_env("MISTRAL_MODEL_LARGE", "codestral-latest"),
  mistral_vision_model: System.get_env("MISTRAL_VISION_MODEL", "ministral-3b-2512"),
  mistral_pass1_model: System.get_env("MISTRAL_PASS1_MODEL", "ministral-3b-latest"),
  mistral_review_model: System.get_env("MISTRAL_REVIEW_MODEL", "mistral-large-latest"),
  whisper_url: System.get_env("WHISPER_URL", "http://127.0.0.1:8000"),
  whisper_provider:
    if(System.get_env("WHISPER_PROVIDER") == "mistral", do: :mistral, else: :local),
  telegram_bot_token: telegram_bot_token,
  telegram_secret_token: read_secret.("telegram_secret_token", "TELEGRAM_SECRET_TOKEN", nil),
  email_webhook_secret:
    if(config_env() == :prod,
      do:
        read_secret.("email_webhook_secret", "EMAIL_WEBHOOK_SECRET", nil) ||
          raise("EMAIL_WEBHOOK_SECRET secret or env var is required in prod"),
      else: read_secret.("email_webhook_secret", "EMAIL_WEBHOOK_SECRET", nil)
    ),
  admin_token:
    if(config_env() == :prod,
      do:
        read_secret.("admin_token", "ADMIN_TOKEN", nil) ||
          raise("ADMIN_TOKEN secret or env var is required in prod"),
      else: read_secret.("admin_token", "ADMIN_TOKEN", "dev-admin-token")
    ),
  storage_path: System.get_env("STORAGE_PATH", "priv/uploads"),
  file_storage:
    if(System.get_env("FILE_STORAGE_BACKEND") == "s3",
      do: CrmReactor.Storage.S3,
      else: CrmReactor.Storage.Local
    ),
  s3_bucket: System.get_env("MINIO_BUCKET", "crm-reactor"),
  ex_aws_config: [
    access_key_id:
      if(config_env() == :prod,
        do:
          read_secret.("minio_root_user", "MINIO_ACCESS_KEY", nil) ||
            raise("MINIO_ACCESS_KEY secret or env var is required in prod"),
        else: read_secret.("minio_root_user", "MINIO_ACCESS_KEY", "minioadmin")
      ),
    secret_access_key:
      if(config_env() == :prod,
        do:
          read_secret.("minio_root_password", "MINIO_SECRET_KEY", nil) ||
            raise("MINIO_SECRET_KEY secret or env var is required in prod"),
        else: read_secret.("minio_root_password", "MINIO_SECRET_KEY", "minioadmin")
      ),
    scheme: System.get_env("MINIO_SCHEME", "http://"),
    host: System.get_env("MINIO_HOST", "localhost"),
    port: String.to_integer(System.get_env("MINIO_PORT", "9000")),
    s3_force_path_style: true
  ],
  bootstrap_token: read_secret.("bootstrap_token", "BOOTSTRAP_TOKEN", nil),
  mailer_from:
    {System.get_env("MAILER_FROM_NAME", "CRM Reactor"),
     System.get_env("MAILER_FROM_EMAIL", "noreply@crm-reactor.app")}

config :telegex, token: telegram_bot_token

cloak_key =
  read_secret.("cloak_key", "CLOAK_KEY", nil) ||
    if config_env() == :prod do
      raise "CLOAK_KEY secret or env var is required in prod"
    else
      Base.encode64(:crypto.strong_rand_bytes(32))
    end

config :crm_reactor, CrmReactor.Vault,
  ciphers: [
    default: {Cloak.Ciphers.AES.GCM, tag: "AES.GCM.V1", key: Base.decode64!(cloak_key)}
  ]

config :crm_reactor, CrmReactor.Encrypted.HMAC,
  algorithm: :sha256,
  secret: System.get_env("CLOAK_HMAC_SECRET", cloak_key)

if config_env() != :test do
  config :crm_reactor, classifier: CrmReactor.AI.Classifier
end

if System.get_env("PHX_SERVER") do
  config :crm_reactor, CrmReactorWeb.Endpoint, server: true
end

if config_env() == :prod do
  database_url =
    read_secret.("database_url", "DATABASE_URL", nil) ||
      raise """
      DATABASE_URL secret or environment variable is missing.
      For example: ecto://USER:PASS@HOST/DATABASE
      """

  maybe_ipv6 = if System.get_env("ECTO_IPV6") in ~w(true 1), do: [:inet6], else: []

  mailjet_api_key =
    read_secret.("mailjet_api_key", "MAILJET_API_KEY", nil) ||
      raise("MAILJET_API_KEY secret or env var is required in prod")

  mailjet_secret_key =
    read_secret.("mailjet_secret_key", "MAILJET_SECRET_KEY", nil) ||
      raise("MAILJET_SECRET_KEY secret or env var is required in prod")

  config :crm_reactor, CrmReactor.Mailer,
    adapter: Swoosh.Adapters.Mailjet,
    api_key: mailjet_api_key,
    secret: mailjet_secret_key

  config :swoosh, :api_client, Swoosh.ApiClient.Req

  config :crm_reactor, CrmReactor.Repo,
    url: database_url,
    pool_size: String.to_integer(System.get_env("POOL_SIZE") || "10"),
    socket_options: maybe_ipv6

  secret_key_base =
    read_secret.("secret_key_base", "SECRET_KEY_BASE", nil) ||
      raise """
      SECRET_KEY_BASE secret or environment variable is missing.
      You can generate one by calling: mix phx.gen.secret
      """

  host = System.get_env("PHX_HOST") || "localhost"
  port = String.to_integer(System.get_env("PORT") || "4000")

  config :crm_reactor, :dns_cluster_query, System.get_env("DNS_CLUSTER_QUERY")

  config :crm_reactor, CrmReactorWeb.Endpoint,
    url: [host: host, port: 443, scheme: "https"],
    http: [
      ip: {0, 0, 0, 0, 0, 0, 0, 0},
      port: port
    ],
    check_origin: [
      "https://#{host}",
      "http://#{host}",
      "http://localhost",
      "https://localhost"
    ],
    secret_key_base: secret_key_base
end
