defmodule HueworksWeb.ConfigHelpers do
  @moduledoc false

  alias Hueworks.HomeKit.Config, as: HomeKitBridgeConfig
  alias Hueworks.Scenes.LightStates

  def homekit_pairing_code(app_setting) do
    app_setting
    |> HomeKitBridgeConfig.from_settings()
    |> Map.fetch!(:pairing_code)
  end

  def api_base_url do
    HueworksWeb.Endpoint.url()
    |> String.trim_trailing("/")
  end

  def format_coord(nil), do: ""

  def format_coord(value) when is_binary(value) do
    case Float.parse(value) do
      {number, _} -> format_coord(number)
      :error -> ""
    end
  end

  def format_coord(value) when is_integer(value), do: format_coord(value * 1.0)
  def format_coord(value) when is_float(value), do: :erlang.float_to_binary(value, decimals: 6)
  def format_coord(_value), do: ""

  def format_integer(value) when is_integer(value), do: Integer.to_string(value)
  def format_integer(_value), do: "0"

  def parse_boolean_param(value) when value in [true, false], do: value
  def parse_boolean_param("true"), do: true
  def parse_boolean_param("false"), do: false
  def parse_boolean_param(_value), do: false

  def timezone_options(current_timezone) do
    base_timezones = [
      "Etc/UTC",
      "America/New_York",
      "America/Chicago",
      "America/Denver",
      "America/Los_Angeles",
      "America/Phoenix",
      "America/Anchorage",
      "Pacific/Honolulu",
      "Europe/London",
      "Europe/Paris",
      "Europe/Berlin",
      "Europe/Madrid",
      "Europe/Rome",
      "Asia/Tokyo",
      "Asia/Seoul",
      "Asia/Shanghai",
      "Asia/Singapore",
      "Asia/Kolkata",
      "Australia/Sydney",
      "Australia/Melbourne",
      "Pacific/Auckland"
    ]

    case normalize_timezone(current_timezone) do
      nil -> base_timezones
      timezone -> Enum.uniq([timezone | base_timezones])
    end
  end

  def state_label(state), do: LightStates.editor_label(state)

  defp normalize_timezone(value) when is_binary(value) do
    trimmed = String.trim(value)
    if trimmed == "", do: nil, else: trimmed
  end

  defp normalize_timezone(_value), do: nil
end
