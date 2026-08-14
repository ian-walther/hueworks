defmodule Hueworks.HomeAssistant.Export.Config do
  @moduledoc false

  alias Hueworks.AppSettings

  @default_port 1883
  @default_discovery_prefix "homeassistant"
  @default_topic_prefix "hueworks/ha_export"

  @enforce_keys [
    :enabled,
    :scenes_enabled,
    :area_selects_enabled,
    :lights_enabled,
    :host,
    :port,
    :username,
    :password,
    :discovery_prefix,
    :configuration_url
  ]
  defstruct enabled: false,
            scenes_enabled: false,
            area_selects_enabled: false,
            lights_enabled: false,
            host: nil,
            port: @default_port,
            username: nil,
            password: nil,
            discovery_prefix: @default_discovery_prefix,
            configuration_url: nil

  def export_config do
    AppSettings.get_global()
    |> from_settings()
  end

  def from_settings(settings) do
    %__MODULE__{
      enabled:
        settings.ha_export_scenes_enabled == true or
          settings.ha_export_area_selects_enabled == true or
          settings.ha_export_lights_enabled == true,
      scenes_enabled: settings.ha_export_scenes_enabled == true,
      area_selects_enabled: settings.ha_export_area_selects_enabled == true,
      lights_enabled: settings.ha_export_lights_enabled == true,
      host: settings.ha_export_mqtt_host,
      port: settings.ha_export_mqtt_port || @default_port,
      username: settings.ha_export_mqtt_username,
      password: settings.ha_export_mqtt_password,
      discovery_prefix: settings.ha_export_discovery_prefix || @default_discovery_prefix,
      configuration_url: Map.get(settings, :ha_export_configuration_url)
    }
  end

  def export_enabled?(%__MODULE__{enabled: true, host: host}) when is_binary(host),
    do: String.trim(host) != ""

  def export_enabled?(_config), do: false

  def scenes_enabled?(%__MODULE__{scenes_enabled: true}), do: true
  def scenes_enabled?(_config), do: false

  def area_selects_enabled?(%__MODULE__{area_selects_enabled: true}), do: true
  def area_selects_enabled?(_config), do: false

  def lights_enabled?(%__MODULE__{lights_enabled: true}), do: true
  def lights_enabled?(_config), do: false

  def same_config?(nil, _config), do: false
  def same_config?(left, right), do: left == right

  def normalize_payload(payload) when is_binary(payload), do: String.trim(payload)
  def normalize_payload(payload), do: IO.iodata_to_binary(payload) |> String.trim()

  def command_topic_filters(topic_prefix \\ @default_topic_prefix) do
    [
      "#{topic_prefix}/scenes/+/set",
      "#{topic_prefix}/areas/+/scene/set",
      "#{topic_prefix}/lights/+/switch/set",
      "#{topic_prefix}/lights/+/light/set",
      "#{topic_prefix}/groups/+/switch/set",
      "#{topic_prefix}/groups/+/light/set",
      "#{topic_prefix}/presence_inputs/+/switch/set"
    ]
  end
end
