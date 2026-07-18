defmodule Hueworks.Import.Fetch.Z2M do
  @moduledoc """
  Fetch Zigbee2MQTT snapshot data over MQTT for import.
  """

  alias Hueworks.Control.Z2MConfig
  alias Hueworks.Import.Fetch.Common
  alias Hueworks.Z2M.Snapshot

  def fetch do
    :z2m
    |> Common.load_enabled_bridge!()
    |> fetch_for_bridge()
  end

  def fetch_for_bridge(bridge) do
    config = config_for_bridge(bridge)

    case Snapshot.fetch(config) do
      {:ok, snapshot} ->
        %{
          broker_host: config.host,
          broker_port: config.port,
          base_topic: config.base_topic,
          bridge_info: snapshot.bridge_info,
          devices: normalize_device_payload(snapshot.devices),
          groups: normalize_group_payload(snapshot.groups)
        }

      {:error, reason} ->
        raise "Z2M fetch failed: #{reason}"
    end
  end

  defp config_for_bridge(bridge) do
    Z2MConfig.for_bridge(bridge)
  end

  defp normalize_device_payload(payload) when is_list(payload), do: payload
  defp normalize_device_payload(%{"devices" => devices}) when is_list(devices), do: devices
  defp normalize_device_payload(_payload), do: []

  defp normalize_group_payload(payload) when is_list(payload), do: payload
  defp normalize_group_payload(%{"groups" => groups}) when is_list(groups), do: groups
  defp normalize_group_payload(_payload), do: []
end
