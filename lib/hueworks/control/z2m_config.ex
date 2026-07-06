defmodule Hueworks.Control.Z2MConfig do
  @moduledoc false

  alias Hueworks.Schemas.Bridge
  alias Hueworks.Util

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
    [user_name: username]
    |> maybe_put_password(password)
  end

  def tortoise_auth_opts(_config), do: []

  defp normalize_base_topic(value) when is_binary(value) do
    value = String.trim(value)
    if value == "", do: @default_base_topic, else: value
  end

  defp normalize_base_topic(_value), do: @default_base_topic

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

  defp maybe_put_password(opts, password) when is_binary(password),
    do: Keyword.put(opts, :password, password)

  defp maybe_put_password(opts, _password), do: opts
end
