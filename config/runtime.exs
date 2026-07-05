import Config

advanced_debug_logging =
  System.get_env("ADVANCED_DEBUG_LOGGING", "false")
  |> String.downcase()
  |> then(&(&1 in ["1", "true", "yes", "on"]))

config :hueworks, :advanced_debug_logging, advanced_debug_logging

homekit_runtime_enabled =
  case System.get_env("HOMEKIT_RUNTIME_ENABLED") do
    nil ->
      Application.get_env(:hueworks, :homekit_runtime_enabled, true)

    value ->
      value
      |> String.downcase()
      |> then(&(&1 in ["1", "true", "yes", "on"]))
  end

config :hueworks, :homekit_runtime_enabled, homekit_runtime_enabled

credentials_root = System.get_env("CREDENTIALS_ROOT")

if is_binary(credentials_root) and String.trim(credentials_root) != "" do
  config :hueworks, :credentials_root, String.trim(credentials_root)
end

homekit_data_path = System.get_env("HOMEKIT_DATA_PATH")

if is_binary(homekit_data_path) and String.trim(homekit_data_path) != "" do
  config :hueworks, :homekit_data_path, String.trim(homekit_data_path)
end

homekit_port =
  case System.get_env("HOMEKIT_PORT") do
    nil ->
      Application.get_env(:hueworks, :homekit_port, 51_827)

    value ->
      String.to_integer(value)
  end

config :hueworks, :homekit_port, homekit_port

homekit_mdns_host =
  case System.get_env("HOMEKIT_MDNS_HOST") do
    nil -> Application.get_env(:hueworks, :homekit_mdns_host, "hueworks")
    value -> String.trim(value)
  end

if is_binary(homekit_mdns_host) and homekit_mdns_host != "" do
  config :hueworks, :homekit_mdns_host, homekit_mdns_host

  config :mdns_lite,
    hosts: [homekit_mdns_host],
    ipv4_only: true
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

  scheme =
    System.get_env("PHX_SCHEME", "http")
    |> String.downcase()
    |> case do
      value when value in ["http", "https"] -> value
      value -> raise "PHX_SCHEME must be http or https, got: #{inspect(value)}"
    end

  default_url_port = if scheme == "https", do: 443, else: port

  url_port =
    case System.get_env("PHX_URL_PORT") do
      nil ->
        default_url_port

      value ->
        case String.trim(value) do
          "" -> default_url_port
          normalized -> String.to_integer(normalized)
        end
    end

  config :hueworks, HueworksWeb.Endpoint,
    url: [host: host, port: url_port, scheme: scheme],
    http: [ip: {0, 0, 0, 0, 0, 0, 0, 0}, port: port],
    secret_key_base: secret_key_base
end
