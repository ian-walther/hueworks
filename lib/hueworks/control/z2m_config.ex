defmodule Hueworks.Control.Z2MConfig do
  @moduledoc false

  alias Hueworks.Schemas.Bridge
  alias Hueworks.Util
  alias Hueworks.Mqtt.Options, as: MqttOptions

  @default_port 1883
  @default_base_topic "zigbee2mqtt"

  def for_bridge(%Bridge{} = bridge) do
    credentials = Bridge.credentials_struct(bridge)

    %{
      bridge_id: bridge.id,
      host: bridge.host,
      base_topic: normalize_base_topic(credentials.base_topic),
      port: normalize_port(credentials.broker_port),
      username: normalize_optional(credentials.username),
      password: normalize_optional(credentials.password)
    }
  end

  def tortoise_auth_opts(%{username: username, password: password}) when is_binary(username) do
    MqttOptions.put_auth([], %{username: username, password: password})
  end

  def tortoise_auth_opts(_config), do: []

  def normalize_base_topic(value) when is_binary(value) do
    value = String.trim(value)
    if value == "", do: @default_base_topic, else: value
  end

  def normalize_base_topic(_value), do: @default_base_topic

  def normalize_port(value) do
    case parse_port(value) do
      port when is_integer(port) -> port
      _ -> @default_port
    end
  end

  def valid_port?(value), do: is_integer(parse_port(value))

  def normalize_optional(value) when is_binary(value) do
    value = String.trim(value)
    if value == "", do: nil, else: value
  end

  def normalize_optional(_value), do: nil

  defp parse_port(value) do
    case Util.parse_optional_integer(value) do
      port when is_integer(port) and port > 0 and port <= 65_535 -> port
      _ -> nil
    end
  end
end
