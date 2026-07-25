import Config

config :hueworks, Hueworks.Repo,
  database: Path.expand("../hueworks_test.db", __DIR__),
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: 10,
  busy_timeout: 10_000

config :hueworks, HueworksWeb.Endpoint,
  url: [host: "localhost", port: 4002, scheme: "http"],
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "Op4X3hwzztmUBfFDqHCl+hQyyrxsOvL+BGEj1wTi3porxlsHiL3JFK9HH638hbC5",
  server: false

config :logger, level: :warning
config :phoenix, :plug_init_mode, :runtime
config :hueworks, :control_executor_enabled, false
config :hueworks, :circadian_poll_enabled, false
config :hueworks, :circadian_poll_interval_ms, 60_000
config :hueworks, :ha_export_runtime_enabled, false
config :hueworks, :homekit_runtime_enabled, false

config :mdns_lite,
  hosts: [],
  ipv4_only: true,
  skip_udp: true

config :tzdata, :autoupdate, :disabled
