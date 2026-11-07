defmodule HueworksWeb.LightStateEditorLive.FormState do
  @moduledoc false

  alias Hueworks.Color
  alias Hueworks.Circadian.Config, as: CircadianConfig
  alias Hueworks.Circadian.Timing
  alias Hueworks.Schemas.LightState
  alias Hueworks.Util

  @manual_keys ["mode", "brightness", "temperature", "hue", "saturation"]

  def manual_keys, do: @manual_keys
  def circadian_form_keys, do: CircadianConfig.supported_keys()

  def from_light_state(%LightState{type: type} = state), do: default_edits(type, state.config)

  def default_edits(type, config \\ %{})
  def default_edits(:manual, config), do: manual_default_edits(config)
  def default_edits(:circadian, config), do: circadian_default_edits(config)

  def new_edits(:manual), do: manual_default_edits()
  def new_edits(:circadian), do: circadian_default_edits(CircadianConfig.new_profile_config())

  @manual_new_defaults %{brightness: 100, kelvin: 3000, hue: 0, saturation: 100}

  def manual_default_edits(config \\ %{}) do
    config = LightState.manual_config(config)
    defaults = if Map.has_key?(config, :brightness), do: %{}, else: @manual_new_defaults

    %{
      "mode" => manual_mode_string(config),
      "brightness" => manual_config_value(config, :brightness, defaults),
      "temperature" => manual_config_value(config, :kelvin, defaults),
      "hue" => manual_config_value(config, :hue, defaults),
      "saturation" => manual_config_value(config, :saturation, defaults)
    }
  end

  def circadian_default_edits(config) do
    defaults =
      CircadianConfig.defaults()
      |> Enum.map(fn {key, value} -> {key, stringify_config_value(value)} end)
      |> Map.new()

    config
    |> normalize_config_entries()
    |> Enum.reduce(defaults, fn {key, value}, acc ->
      normalized_key = normalize_config_key(key)

      if normalized_key in circadian_form_keys() and not is_nil(value) do
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
          current_config
          |> Map.merge(Map.take(params, manual_keys()))
          |> Map.put_new("mode", "temperature")

        :circadian ->
          # Controls locked when the form rendered cannot submit a real edit, and
          # a value for one must not replace the local value stored behind it.
          editable_keys = circadian_form_keys() -- locked_circadian_keys(current_config)

          Map.merge(current_config, Map.take(params, editable_keys))
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

  def circadian_field_value(config, key) do
    config
    |> Map.get(normalize_config_key(key), "")
  end

  def circadian_time_value(config, key) do
    config
    |> circadian_field_value(key)
    |> case do
      nil -> ""
      value -> value
    end
  end

  def circadian_brightness_mode(config) do
    case circadian_field_value(config, :brightness_mode) do
      "" -> "tanh"
      value -> value
    end
  end

  def timing_override?(config, event) do
    config
    |> Map.get(Timing.override_field(event))
    |> Util.parse_optional_bool()
    |> Kernel.!=(false)
  end

  def timing_locked?(config, key) do
    normalize_config_key(key) in locked_circadian_keys(config)
  end

  @doc """
  The value a control shows: the effective value while it is locked, otherwise
  the value being edited. Stored local values stay in the config underneath.
  """
  def circadian_display_value(config, key, global_timing) do
    key = normalize_config_key(key)

    case locked_display_values(config, global_timing) do
      %{^key => value} -> stringify_config_value(value)
      _unlocked -> circadian_field_value(config, key)
    end
  end

  def timing_note(config, event, global_timing) do
    if timing_override?(config, event) do
      "Uses this light state's #{event} timing and window. Global bounds do not apply."
    else
      "Inherits astronomical #{event} with #{global_bounds_label(event, global_timing)}, " <>
        "no offsets, and default ramps. Values stored here are kept for a later override."
    end
  end

  def ramp_note(config) do
    %{dark_seconds: dark, light_seconds: light} = Timing.default_ramp()
    defaults = "#{dark} s dark and #{light} s light"

    case {timing_override?(config, :sunrise), timing_override?(config, :sunset)} do
      {true, true} ->
        nil

      {false, false} ->
        "Both events inherit, so they use the defaults: #{defaults}. Stored durations are kept."

      {true, false} ->
        "These durations apply only around sunrise. Sunset uses the defaults: #{defaults}."

      {false, true} ->
        "These durations apply only around sunset. Sunrise uses the defaults: #{defaults}."
    end
  end

  def manual_color_preview_style(config) do
    {r, g, b} = manual_color_rgb(config) || {143, 177, 255}
    "--hw-color-preview: #{r} #{g} #{b};"
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

    "--hw-saturation-start: #{r1} #{g1} #{b1}; --hw-saturation-end: #{r2} #{g2} #{b2};"
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

    case Util.blank_to_nil(current_timezone) do
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

  defp locked_circadian_keys(config) do
    sunrise_override? = timing_override?(config, :sunrise)
    sunset_override? = timing_override?(config, :sunset)

    [
      {sunrise_override?, Timing.event_fields(:sunrise)},
      {sunset_override?, Timing.event_fields(:sunset)},
      {sunrise_override? or sunset_override?, Timing.ramp_fields()}
    ]
    |> Enum.reject(fn {editable?, _keys} -> editable? end)
    |> Enum.flat_map(fn {_editable?, keys} -> keys end)
  end

  defp locked_display_values(config, global_timing) do
    [:sunrise, :sunset]
    |> Enum.reject(&timing_override?(config, &1))
    |> Enum.map(&Timing.inherited_values(&1, global_timing))
    |> Enum.reduce(locked_ramp_values(config), &Map.merge/2)
  end

  defp locked_ramp_values(config) do
    if timing_override?(config, :sunrise) or timing_override?(config, :sunset) do
      %{}
    else
      Map.take(CircadianConfig.defaults(), Timing.ramp_fields())
    end
  end

  defp global_bounds_label(event, global_timing) do
    case Timing.global_bounds(event, global_timing) do
      {nil, nil} -> "no global bounds"
      {min, nil} -> "a global minimum of #{min}"
      {nil, max} -> "a global maximum of #{max}"
      {min, max} -> "global bounds of #{min} to #{max}"
    end
  end

  defp manual_config_value(config, key, defaults) do
    case Map.get(config, key) do
      nil -> Map.get(defaults, key, "")
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

  defp normalize_config_entries(%_{} = config), do: Map.from_struct(config)
  defp normalize_config_entries(config) when is_map(config), do: config
  defp normalize_config_entries(_config), do: %{}
end
