defmodule Hueworks.Control.Z2MBridge do
  @moduledoc false

  alias Hueworks.Repo
  alias Hueworks.Schemas.Bridge
  alias Hueworks.Util
  alias HueworksApp.Cache

  @default_port 1883
  @default_base_topic "zigbee2mqtt"
  @cache_namespace :bridge_credentials
  @default_ttl_ms 10_000

  def connection_for(%{bridge_id: bridge_id}) when is_integer(bridge_id) do
    Cache.get_or_load(
      @cache_namespace,
      {:z2m, bridge_id},
      fn -> load_connection(bridge_id) end,
      ttl_ms: credentials_cache_ttl_ms()
    )
  end

  def connection_for(_entity), do: {:error, :missing_bridge_id}

  defp normalize_port(value) do
    case Util.parse_optional_integer(value) do
      port when is_integer(port) and port > 0 and port <= 65_535 -> port
      _ -> @default_port
    end
  end

  defp normalize_optional(value) when is_binary(value) do
    value = String.trim(value)
    if value == "", do: nil, else: value
  end

  defp normalize_optional(_value), do: nil

  defp normalize_base_topic(value) when is_binary(value) do
    value = String.trim(value)
    if value == "", do: @default_base_topic, else: value
  end

  defp normalize_base_topic(_value), do: @default_base_topic

  defp load_connection(bridge_id) do
    case Repo.get(Bridge, bridge_id) do
      nil ->
        {:error, :bridge_not_found}

      %Bridge{} = bridge ->
        credentials = Bridge.credentials_struct(bridge)

        {:ok,
         %{
           bridge_id: bridge.id,
           host: bridge.host,
           port: normalize_port(credentials.broker_port),
           username: normalize_optional(credentials.username),
           password: normalize_optional(credentials.password),
           base_topic: normalize_base_topic(credentials.base_topic)
         }}
    end
  end

  defp credentials_cache_ttl_ms do
    Application.get_env(:hueworks, :cache_bridge_credentials_ttl_ms, @default_ttl_ms)
  end
end
