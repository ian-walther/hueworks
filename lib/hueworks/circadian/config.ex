defmodule Hueworks.Circadian.Config do
  @moduledoc """
  Validation and normalization for scene-level circadian settings.

  Key names intentionally mirror Home Assistant Adaptive Lighting calculation
  options, excluding sleep-mode and RGB-related settings.
  """

  @brightness_modes ~w(default linear tanh)

  @supported_keys [
    "min_brightness",
    "max_brightness",
    "min_color_temp",
    "max_color_temp",
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
    "brightness_mode_time_light"
  ]

  @defaults %{
    "min_brightness" => 1,
    "max_brightness" => 100,
    "min_color_temp" => 2000,
    "max_color_temp" => 5500,
    "sunrise_time" => nil,
    "min_sunrise_time" => nil,
    "max_sunrise_time" => nil,
    "sunrise_offset" => 0,
    "sunset_time" => nil,
    "min_sunset_time" => nil,
    "max_sunset_time" => nil,
    "sunset_offset" => 0,
    "brightness_mode" => "default",
    "brightness_mode_time_dark" => 900,
    "brightness_mode_time_light" => 3600
  }

  def supported_keys, do: @supported_keys
  def defaults, do: @defaults

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
  defp normalize_value("sunrise_offset", value), do: parse_offset_seconds(value)
  defp normalize_value("sunset_offset", value), do: parse_offset_seconds(value)
  defp normalize_value("brightness_mode_time_dark", value), do: parse_non_negative_seconds(value)
  defp normalize_value("brightness_mode_time_light", value), do: parse_non_negative_seconds(value)

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

  defp parse_int_in_range(value, min, max) do
    case parse_integer(value) do
      {:ok, parsed} when parsed >= min and parsed <= max -> {:ok, parsed}
      {:ok, _parsed} -> {:error, "must be between #{min} and #{max}"}
      {:error, _reason} -> {:error, "must be an integer between #{min} and #{max}"}
    end
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
end
