import Config

config :hueworks, Hueworks.Repo,
  database: Path.expand("../hueworks_dev.db", __DIR__),
  stacktrace: true,
  show_sensitive_data_on_connection_error: true

config :hueworks, HueworksWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4000],
  check_origin: false,
  code_reloader: true,
  debug_errors: true,
  secret_key_base: "development_secret_key_base_at_least_64_bytes_long_for_security",
  watchers: [
    esbuild: {Esbuild, :install_and_run, [:hueworks, ~w(--sourcemap=inline --watch)]},
    tailwind: {Tailwind, :install_and_run, [:hueworks, ~w(--watch)]}
  ],
  live_reload: [
    patterns: [
      ~r"priv/static/(?!uploads/).*(js|css|png|jpeg|jpg|gif|svg)$",
      ~r"lib/hueworks_web/(controllers|live|components)/.*(ex|heex)$"
    ]
  ]

config :logger, :console, format: "[$level] $message\n"

config :phoenix, :stacktrace_depth, 20
config :phoenix, :plug_init_mode, :runtime
