defmodule Hueworks.HomeAssistant.Export.Config do
  @moduledoc false

  @default_port 1883
  @default_discovery_prefix "homeassistant"

  @enforce_keys [
    :enabled,
    :scenes_enabled,
    :room_selects_enabled,
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
            room_selects_enabled: false,
            lights_enabled: false,
            host: nil,
            port: @default_port,
            username: nil,
            password: nil,
            discovery_prefix: @default_discovery_prefix,
            configuration_url: nil

  def from_settings(settings) do
    %__MODULE__{
      enabled:
        settings.ha_export_scenes_enabled == true or
          settings.ha_export_room_selects_enabled == true or
          settings.ha_export_lights_enabled == true,
      scenes_enabled: settings.ha_export_scenes_enabled == true,
      room_selects_enabled: settings.ha_export_room_selects_enabled == true,
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

  def room_selects_enabled?(%__MODULE__{room_selects_enabled: true}), do: true
  def room_selects_enabled?(_config), do: false

  def lights_enabled?(%__MODULE__{lights_enabled: true}), do: true
  def lights_enabled?(_config), do: false
end
