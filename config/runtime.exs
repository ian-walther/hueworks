import Config

advanced_debug_logging =
  System.get_env("ADVANCED_DEBUG_LOGGING", "false")
  |> String.downcase()
  |> then(&(&1 in ["1", "true", "yes", "on"]))

config :hueworks, :advanced_debug_logging, advanced_debug_logging

credentials_root = System.get_env("CREDENTIALS_ROOT")

if is_binary(credentials_root) and String.trim(credentials_root) != "" do
  config :hueworks, :credentials_root, String.trim(credentials_root)
end

# Runtime configuration (can read from environment variables)
if config_env() == :prod do
  if System.get_env("PHX_SERVER") do
    config :hueworks, HueworksWeb.Endpoint, server: true
  end

  database_path =
    System.get_env("DATABASE_PATH") ||
      raise """
      environment variable DATABASE_PATH is missing.
      For example: /etc/hueworks/hueworks.db
      """

  config :hueworks, Hueworks.Repo,
    database: database_path,
    pool_size: String.to_integer(System.get_env("POOL_SIZE") || "5")

  secret_key_base =
    System.get_env("SECRET_KEY_BASE") ||
      raise """
      environment variable SECRET_KEY_BASE is missing.
      You can generate one by calling: mix phx.gen.secret
      """

  host = System.get_env("PHX_HOST") || "localhost"
  port = String.to_integer(System.get_env("PORT") || "4000")

  config :hueworks, HueworksWeb.Endpoint,
    url: [host: host, port: 443, scheme: "https"],
    http: [ip: {0, 0, 0, 0, 0, 0, 0, 0}, port: port],
    secret_key_base: secret_key_base
end
