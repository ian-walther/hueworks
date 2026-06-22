defmodule Hueworks.HomeAssistant.Export.Runtime do
  @moduledoc false

  alias Hueworks.AppSettings
  alias Hueworks.HomeAssistant.Export.Config

  @default_topic_prefix "hueworks/ha_export"

  def export_config do
    AppSettings.get_global()
    |> Config.from_settings()
  end

  defdelegate export_enabled?(config), to: Config

  defdelegate scenes_enabled?(config), to: Config

  defdelegate room_selects_enabled?(config), to: Config

  defdelegate lights_enabled?(config), to: Config

  def same_config?(nil, _config), do: false
  def same_config?(left, right), do: left == right

  def normalize_payload(payload) when is_binary(payload), do: String.trim(payload)
  def normalize_payload(payload), do: IO.iodata_to_binary(payload) |> String.trim()

  def command_topic_filters(topic_prefix \\ @default_topic_prefix) do
    [
      "#{topic_prefix}/scenes/+/set",
      "#{topic_prefix}/rooms/+/scene/set",
      "#{topic_prefix}/lights/+/switch/set",
      "#{topic_prefix}/lights/+/light/set",
      "#{topic_prefix}/groups/+/switch/set",
      "#{topic_prefix}/groups/+/light/set"
    ]
  end
end
