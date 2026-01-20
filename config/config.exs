import Config

# Configure Ecto Repo
config :hueworks, Hueworks.Repo,
  database: Path.expand("../hueworks_#{config_env()}.db", __DIR__),
  pool_size: 5

config :hueworks,
  ecto_repos: [Hueworks.Repo]

# Configure Phoenix endpoint
config :hueworks, HueworksWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: HueworksWeb.ErrorHTML],
    layout: false
  ],
  pubsub_server: Hueworks.PubSub,
  live_view: [signing_salt: "hueworks_secret_salt"]

# Configure esbuild
config :esbuild,
  version: "0.17.11",
  hueworks: [
    args: ~w(js/app.js --bundle --target=es2017 --outdir=../priv/static/assets --external:/fonts/* --external:/images/*),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => Path.expand("../deps", __DIR__)}
  ]

# Configure tailwind
config :tailwind,
  version: "3.4.0",
  hueworks: [
    args: ~w(
      --config=tailwind.config.js
      --input=css/app.css
      --output=../priv/static/assets/app.css
    ),
    cd: Path.expand("../assets", __DIR__)
  ]

# Configure logger
config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:bridge_type, :device_id, :request_id]

# Configure MIME types for credential uploads
config :mime, :types, %{
  "application/x-x509-ca-cert" => ["crt"],
  "application/x-pem-file" => ["pem"],
  "application/pkcs8" => ["key"]
}

# Import environment specific config
import_config "#{config_env()}.exs"
