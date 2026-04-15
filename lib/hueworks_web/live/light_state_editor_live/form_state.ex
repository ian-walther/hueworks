defmodule HueworksWeb.LightStateEditorLive.FormState do
  @moduledoc false

  alias Hueworks.Color
  alias Hueworks.Circadian.Config, as: CircadianConfig
  alias Hueworks.Schemas.LightState
  alias Hueworks.Util

  @manual_keys ["mode", "brightness", "temperature", "hue", "saturation"]

  def manual_keys, do: @manual_keys
  def circadian_form_keys, do: CircadianConfig.supported_keys()

  def default_edits(type, config \\ %{})
  def default_edits(:manual, config), do: manual_default_edits(config)
  def default_edits(:circadian, config), do: circadian_default_edits(config)

  def manual_default_edits(config \\ %{}) do
    config = LightState.manual_config(config)

    %{
      "mode" => manual_mode_string(config),
      "brightness" => manual_config_value(config, :brightness),
      "temperature" => manual_config_value(config, :kelvin),
      "hue" => manual_config_value(config, :hue),
      "saturation" => manual_config_value(config, :saturation)
    }
  end

  def circadian_default_edits(config) do
    defaults =
      CircadianConfig.defaults()
      |> Enum.map(fn {key, value} -> {key, stringify_config_value(value)} end)
      |> Map.new()

    config
    |> Enum.reduce(defaults, fn {key, value}, acc ->
      normalized_key = normalize_config_key(key)

      if normalized_key in circadian_form_keys() do
        Map.put(acc, normalized_key, stringify_config_value(value))
      else
        acc
      end
    end)
  end

  def merge_form_params(type, current_name, current_config, params) do
    name = Map.get(params, "name", current_name)

    config =
      case type do
        :manual ->
          manual_keys()
          |> Enum.reduce(current_config, fn key, acc ->
            if Map.has_key?(params, key), do: Map.put(acc, key, Map.get(params, key)), else: acc
          end)
          |> Map.put_new("mode", "temperature")

        :circadian ->
          circadian_form_keys()
          |> Enum.reduce(current_config, fn key, acc ->
            if Map.has_key?(params, key), do: Map.put(acc, key, Map.get(params, key)), else: acc
          end)
      end

    {name, config}
  end

  def merge_preview_params(current_assigns, params) do
    timezone = Map.get(params, "preview_timezone", current_assigns.preview_timezone)

    %{
      preview_date: Map.get(params, "preview_date", current_assigns.preview_date),
      preview_latitude: Map.get(params, "preview_latitude", current_assigns.preview_latitude),
      preview_longitude: Map.get(params, "preview_longitude", current_assigns.preview_longitude),
      preview_timezone: timezone,
      preview_timezones: timezone_options(timezone)
    }
  end

  def manual_mode(config) do
    config
    |> LightState.manual_mode()
    |> manual_mode_string()
  end

  def manual_field_value(config, key) do
    config
    |> LightState.manual_config()
    |> Map.get(key)
    |> case do
      nil -> ""
      value -> value
    end
  end

  def manual_color_preview_style(config) do
    {r, g, b} = manual_color_rgb(config) || {143, 177, 255}
    "background-color: rgb(#{r} #{g} #{b});"
  end

  def manual_color_preview_label(config) do
    config = LightState.manual_config(config)
    hue = Map.get(config, :hue) |> normalize_preview_number(0)
    saturation = Map.get(config, :saturation) |> normalize_preview_number(100)
    brightness = Map.get(config, :brightness) |> normalize_preview_number(100)

    "Preview: #{hue}°, #{saturation}% saturation, #{brightness}% brightness"
  end

  def manual_saturation_scale_style(config) do
    config = LightState.manual_config(config)
    hue = Map.get(config, :hue) |> normalize_preview_number(0)
    brightness = Map.get(config, :brightness) |> normalize_preview_number(100)

    {r1, g1, b1} = Color.hsb_to_rgb(hue, 0, brightness) || {255, 255, 255}
    {r2, g2, b2} = Color.hsb_to_rgb(hue, 100, brightness) || {255, 255, 255}

    "background: linear-gradient(90deg, rgb(#{r1} #{g1} #{b1}), rgb(#{r2} #{g2} #{b2}));"
  end

  def manual_color_rgb(config) do
    config = LightState.manual_config(config)

    Color.hsb_to_rgb(
      Map.get(config, :hue),
      Map.get(config, :saturation),
      Map.get(config, :brightness)
    )
  end

  def default_preview_date(timezone) do
    case DateTime.now(timezone) do
      {:ok, datetime} -> Date.to_iso8601(DateTime.to_date(datetime))
      {:error, _reason} -> Date.to_iso8601(Date.utc_today())
    end
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
      "Australia/Sydney"
    ]

    case normalize_timezone(current_timezone) do
      nil -> base_timezones
      timezone -> Enum.uniq([timezone | base_timezones])
    end
  end

  defp normalize_preview_number(value, fallback) do
    case Util.to_number(value) do
      number when is_number(number) -> round(number)
      _ -> fallback
    end
  end

  defp manual_config_value(config, key) do
    case Map.get(config, key) do
      nil -> ""
      value -> value
    end
  end

  defp manual_mode_string(config) do
    case config do
      :color ->
        "color"

      _ when is_atom(config) ->
        "temperature"

      _ ->
        case LightState.manual_mode(config) do
          :color -> "color"
          _ -> "temperature"
        end
    end
  end

  defp stringify_config_value(nil), do: ""
  defp stringify_config_value(value) when is_binary(value), do: value
  defp stringify_config_value(value) when is_integer(value), do: Integer.to_string(value)
  defp stringify_config_value(value) when is_float(value), do: Float.to_string(value)
  defp stringify_config_value(value), do: to_string(value)

  defp normalize_config_key(key) when is_atom(key), do: Atom.to_string(key)
  defp normalize_config_key(key) when is_binary(key), do: key
  defp normalize_config_key(key), do: to_string(key)

  defp normalize_timezone(value) when is_binary(value) do
    trimmed = String.trim(value)
    if trimmed == "", do: nil, else: trimmed
  end

  defp normalize_timezone(_value), do: nil
end
