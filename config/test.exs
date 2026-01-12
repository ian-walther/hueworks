import Config

config :hueworks, Hueworks.Repo,
  database: Path.expand("../hueworks_test.db", __DIR__),
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: 10

config :hueworks, HueworksWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "test_secret_key_base_at_least_64_bytes_long_for_security_testing",
  server: false

config :logger, level: :warning
config :phoenix, :plug_init_mode, :runtime
