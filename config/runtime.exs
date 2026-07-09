import Config

config :crm_reactor,
  mistral_api_key: System.get_env("MISTRAL_API_KEY"),
  mistral_model_small: System.get_env("MISTRAL_MODEL_SMALL", "mistral-small-latest"),
  mistral_model_large: System.get_env("MISTRAL_MODEL_LARGE", "codestral-latest"),
  mistral_vision_model: System.get_env("MISTRAL_VISION_MODEL", "ministral-3b-2512"),
  mistral_pass1_model: System.get_env("MISTRAL_PASS1_MODEL", "ministral-3b-latest"),
  mistral_review_model: System.get_env("MISTRAL_REVIEW_MODEL", "mistral-large-latest"),
  whisper_url: System.get_env("WHISPER_URL", "http://localhost:8000"),
  telegram_bot_token: System.get_env("TELEGRAM_BOT_TOKEN"),
  telegram_secret_token: System.get_env("TELEGRAM_SECRET_TOKEN"),
  admin_token:
    if(config_env() == :test,
      do: "dev-admin-token",
      else: System.get_env("ADMIN_TOKEN", "dev-admin-token")
    ),
  ollama_url: System.get_env("OLLAMA_URL", "http://127.0.0.1:11435"),
  ollama_model: System.get_env("OLLAMA_MODEL", "qwen2.5:7b"),
  embedding_model: System.get_env("OLLAMA_EMBEDDING_MODEL", "mxbai-embed-large"),
  storage_path: System.get_env("STORAGE_PATH", "priv/uploads")

cloak_key =
  System.get_env("CLOAK_KEY") ||
    Base.encode64(:crypto.strong_rand_bytes(32))

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
    System.get_env("DATABASE_URL") ||
      raise """
      environment variable DATABASE_URL is missing.
      For example: ecto://USER:PASS@HOST/DATABASE
      """

  maybe_ipv6 = if System.get_env("ECTO_IPV6") in ~w(true 1), do: [:inet6], else: []

  config :crm_reactor, CrmReactor.Repo,
    url: database_url,
    pool_size: String.to_integer(System.get_env("POOL_SIZE") || "10"),
    socket_options: maybe_ipv6

  secret_key_base =
    System.get_env("SECRET_KEY_BASE") ||
      raise """
      environment variable SECRET_KEY_BASE is missing.
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
    secret_key_base: secret_key_base
end
