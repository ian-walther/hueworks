defmodule Hueworks.Circadian.Config do
  @moduledoc """
  Validation and normalization for scene-level circadian settings.

  Key names intentionally mirror Home Assistant Adaptive Lighting calculation
  options, excluding sleep-mode and RGB-related settings.
  """

  @brightness_modes ~w(quadratic linear tanh)
  @runtime_mode_map %{"quadratic" => :quadratic, "linear" => :linear, "tanh" => :tanh}

  @supported_keys [
    "min_brightness",
    "max_brightness",
    "min_color_temp",
    "max_color_temp",
    "temperature_ceiling_kelvin",
    "sunrise_time",
    "min_sunrise_time",
    "max_sunrise_time",
    "sunrise_offset",
    "sunset_time",
    "min_sunset_time",
    "max_sunset_time",
    "sunset_offset",
    "brightness_mode",
    "brightness_mode_time_dark",
    "brightness_mode_time_light",
    "brightness_sunrise_offset",
    "brightness_sunset_offset",
    "temperature_sunrise_offset",
    "temperature_sunset_offset"
  ]

  @supported_key_atoms [
    :min_brightness,
    :max_brightness,
    :min_color_temp,
    :max_color_temp,
    :temperature_ceiling_kelvin,
    :sunrise_time,
    :min_sunrise_time,
    :max_sunrise_time,
    :sunrise_offset,
    :sunset_time,
    :min_sunset_time,
    :max_sunset_time,
    :sunset_offset,
    :brightness_mode,
    :brightness_mode_time_dark,
    :brightness_mode_time_light,
    :brightness_sunrise_offset,
    :brightness_sunset_offset,
    :temperature_sunrise_offset,
    :temperature_sunset_offset
  ]

  @supported_key_atom_set MapSet.new(@supported_key_atoms)

  @defaults %{
    "min_brightness" => 1,
    "max_brightness" => 100,
    "min_color_temp" => 2000,
    "max_color_temp" => 5500,
    "temperature_ceiling_kelvin" => nil,
    "sunrise_time" => nil,
    "min_sunrise_time" => nil,
    "max_sunrise_time" => nil,
    "sunrise_offset" => 0,
    "sunset_time" => nil,
    "min_sunset_time" => nil,
    "max_sunset_time" => nil,
    "sunset_offset" => 0,
    "brightness_mode" => "tanh",
    "brightness_mode_time_dark" => 900,
    "brightness_mode_time_light" => 3600,
    "brightness_sunrise_offset" => 0,
    "brightness_sunset_offset" => 0,
    "temperature_sunrise_offset" => 0,
    "temperature_sunset_offset" => 0
  }

  def supported_keys, do: @supported_keys
  def defaults, do: @defaults

  def runtime(config) when is_map(config) do
    config
    |> stringify_keys()
    |> then(&Map.merge(@defaults, &1))
    |> normalize()
    |> case do
      {:ok, normalized} -> {:ok, atomize_runtime_config(normalized)}
      {:error, _reason} = error -> error
    end
  end

  def runtime(_config), do: {:error, [{"config", "must be a map"}]}

  def normalize(config) when is_map(config) do
    config = stringify_keys(config)

    {normalized, errors} =
      Enum.reduce(config, {%{}, []}, fn {key, value}, {acc, errs} ->
        cond do
          key not in @supported_keys ->
            {acc, [{key, "is not supported"} | errs]}

          true ->
            case normalize_value(key, value) do
              {:ok, normalized_value} ->
                {Map.put(acc, key, normalized_value), errs}

              {:error, reason} ->
                {acc, [{key, reason} | errs]}
            end
        end
      end)

    errors =
      errors
      |> validate_min_max_order(normalized, "min_brightness", "max_brightness")
      |> validate_min_max_order(normalized, "min_color_temp", "max_color_temp")
      |> validate_ceiling_order(normalized, "temperature_ceiling_kelvin", "min_color_temp", "max_color_temp")
      |> validate_time_order(normalized, "min_sunrise_time", "max_sunrise_time")
      |> validate_time_order(normalized, "min_sunset_time", "max_sunset_time")

    case errors do
      [] -> {:ok, normalized}
      _ -> {:error, Enum.reverse(errors)}
    end
  end

  def normalize(_config), do: {:error, [{"config", "must be a map"}]}

  defp normalize_value("min_brightness", value), do: parse_int_in_range(value, 1, 100)
  defp normalize_value("max_brightness", value), do: parse_int_in_range(value, 1, 100)
  defp normalize_value("min_color_temp", value), do: parse_int_in_range(value, 1000, 10_000)
  defp normalize_value("max_color_temp", value), do: parse_int_in_range(value, 1000, 10_000)
  defp normalize_value("temperature_ceiling_kelvin", value), do: parse_int_in_range_or_none(value, 1000, 10_000)
  defp normalize_value("sunrise_offset", value), do: parse_offset_seconds(value)
  defp normalize_value("sunset_offset", value), do: parse_offset_seconds(value)
  defp normalize_value("brightness_mode_time_dark", value), do: parse_non_negative_seconds(value)
  defp normalize_value("brightness_mode_time_light", value), do: parse_non_negative_seconds(value)
  defp normalize_value("brightness_sunrise_offset", value), do: parse_offset_seconds(value)
  defp normalize_value("brightness_sunset_offset", value), do: parse_offset_seconds(value)
  defp normalize_value("temperature_sunrise_offset", value), do: parse_offset_seconds(value)
  defp normalize_value("temperature_sunset_offset", value), do: parse_offset_seconds(value)

  defp normalize_value("brightness_mode", value) do
    mode =
      case value do
        atom when is_atom(atom) -> Atom.to_string(atom)
        string when is_binary(string) -> String.trim(string)
        _ -> nil
      end

    if mode in @brightness_modes do
      {:ok, mode}
    else
      {:error, "must be one of: #{Enum.join(@brightness_modes, ", ")}"}
    end
  end

  defp normalize_value(key, value)
       when key in [
              "sunrise_time",
              "min_sunrise_time",
              "max_sunrise_time",
              "sunset_time",
              "min_sunset_time",
              "max_sunset_time"
            ] do
    parse_time_or_none(value)
  end

  defp stringify_keys(config) do
    Enum.reduce(config, %{}, fn {key, value}, acc ->
      normalized_key =
        case key do
          atom when is_atom(atom) -> Atom.to_string(atom)
          binary when is_binary(binary) -> binary
          other -> to_string(other)
        end

      Map.put(acc, normalized_key, value)
    end)
  end

  defp atomize_runtime_config(config) do
    Enum.reduce(config, %{}, fn {key, value}, acc ->
      case runtime_key_atom(key) do
        nil ->
          acc

        :brightness_mode ->
          Map.put(acc, :brightness_mode, Map.fetch!(@runtime_mode_map, value))

        atom_key ->
          Map.put(acc, atom_key, value)
      end
    end)
  end

  defp runtime_key_atom(key) when is_binary(key) do
    case existing_atom_or(key) do
      atom when is_atom(atom) ->
        if MapSet.member?(@supported_key_atom_set, atom), do: atom, else: nil

      _ ->
        nil
    end
  end

  defp runtime_key_atom(key) when is_atom(key) do
    if MapSet.member?(@supported_key_atom_set, key), do: key, else: nil
  end

  defp runtime_key_atom(_key), do: nil

  defp parse_int_in_range(value, min, max) do
    case parse_integer(value) do
      {:ok, parsed} when parsed >= min and parsed <= max -> {:ok, parsed}
      {:ok, _parsed} -> {:error, "must be between #{min} and #{max}"}
      {:error, _reason} -> {:error, "must be an integer between #{min} and #{max}"}
    end
  end

  defp parse_int_in_range_or_none(nil, _min, _max), do: {:ok, nil}
  defp parse_int_in_range_or_none("", _min, _max), do: {:ok, nil}

  defp parse_int_in_range_or_none(value, min, max) do
    parse_int_in_range(value, min, max)
  end

  defp parse_non_negative_seconds(value) do
    case parse_duration_seconds(value) do
      {:ok, seconds} when seconds >= 0 -> {:ok, seconds}
      {:ok, _seconds} -> {:error, "must be a non-negative number of seconds"}
      {:error, _reason} -> {:error, "must be a duration in seconds or HH:MM[:SS]"}
    end
  end

  defp parse_offset_seconds(value) do
    case parse_duration_seconds(value) do
      {:ok, seconds} -> {:ok, seconds}
      {:error, _reason} -> {:error, "must be seconds or +/-HH:MM[:SS]"}
    end
  end

  defp parse_time_or_none(nil), do: {:ok, nil}
  defp parse_time_or_none(""), do: {:ok, nil}
  defp parse_time_or_none("None"), do: {:ok, nil}

  defp parse_time_or_none(value) when is_binary(value) do
    value =
      value
      |> String.trim()
      |> maybe_expand_hours_minutes()

    case Time.from_iso8601(value) do
      {:ok, time} ->
        {:ok, Time.to_iso8601(time)}

      {:error, _reason} ->
        {:error, "must be HH:MM[:SS] or None"}
    end
  end

  defp parse_time_or_none(_value), do: {:error, "must be HH:MM[:SS] or None"}

  defp maybe_expand_hours_minutes(value) do
    if Regex.match?(~r/^\d{1,2}:\d{2}$/, value), do: value <> ":00", else: value
  end

  defp parse_duration_seconds(value) do
    case parse_integer(value) do
      {:ok, seconds} ->
        {:ok, seconds}

      {:error, _reason} ->
        parse_hms_duration(value)
    end
  end

  defp parse_hms_duration(value) when is_binary(value) do
    value = String.trim(value)

    case Regex.run(~r/^(-)?(\d{1,2}):(\d{2})(?::(\d{2}))?$/, value) do
      [_, sign, hours, minutes, seconds] ->
        seconds = if seconds in [nil, ""], do: "0", else: seconds
        minutes_int = String.to_integer(minutes)
        seconds_int = String.to_integer(seconds)

        if minutes_int > 59 or seconds_int > 59 do
          {:error, :invalid}
        else
          total = String.to_integer(hours) * 3600 + minutes_int * 60 + seconds_int
          if sign == "-", do: {:ok, -total}, else: {:ok, total}
        end

      [_, sign, hours, minutes] ->
        minutes_int = String.to_integer(minutes)

        if minutes_int > 59 do
          {:error, :invalid}
        else
          total = String.to_integer(hours) * 3600 + minutes_int * 60
          if sign == "-", do: {:ok, -total}, else: {:ok, total}
        end

      _ ->
        {:error, :invalid}
    end
  end

  defp parse_hms_duration(_value), do: {:error, :invalid}

  defp parse_integer(value) when is_integer(value), do: {:ok, value}

  defp parse_integer(value) when is_float(value) do
    if Float.floor(value) == value do
      {:ok, trunc(value)}
    else
      {:error, :not_integer}
    end
  end

  defp parse_integer(value) when is_binary(value) do
    value = String.trim(value)

    case Integer.parse(value) do
      {parsed, ""} -> {:ok, parsed}
      _ -> {:error, :not_integer}
    end
  end

  defp parse_integer(_value), do: {:error, :not_integer}

  defp validate_min_max_order(errors, config, min_key, max_key) do
    min = Map.get(config, min_key)
    max = Map.get(config, max_key)

    if is_integer(min) and is_integer(max) and min > max do
      [
        {min_key, "must be less than or equal to #{max_key}"},
        {max_key, "must be greater than or equal to #{min_key}"}
        | errors
      ]
    else
      errors
    end
  end

  defp validate_time_order(errors, config, min_key, max_key) do
    min = Map.get(config, min_key)
    max = Map.get(config, max_key)

    with min when is_binary(min) <- min,
         max when is_binary(max) <- max,
         {:ok, min_time} <- Time.from_iso8601(min),
         {:ok, max_time} <- Time.from_iso8601(max),
         :gt <- Time.compare(min_time, max_time) do
      [
        {min_key, "must be less than or equal to #{max_key}"},
        {max_key, "must be greater than or equal to #{min_key}"}
        | errors
      ]
    else
      _ -> errors
    end
  end

  defp validate_ceiling_order(errors, config, ceiling_key, min_key, max_key) do
    ceiling = Map.get(config, ceiling_key)
    min_value = Map.get(config, min_key)
    max_value = Map.get(config, max_key)

    cond do
      is_nil(ceiling) ->
        errors

      is_integer(min_value) and ceiling < min_value ->
        [{ceiling_key, "must be greater than or equal to #{min_key}"} | errors]

      is_integer(max_value) and ceiling > max_value ->
        [{ceiling_key, "must be less than or equal to #{max_key}"} | errors]

      true ->
        errors
    end
  end

  defp existing_atom_or(key, default \\ nil)

  defp existing_atom_or(key, _default) when is_atom(key), do: key

  defp existing_atom_or(key, default) when is_binary(key) do
    try do
      String.to_existing_atom(key)
    rescue
      ArgumentError -> default
    end
  end

  defp existing_atom_or(_key, default), do: default
end
