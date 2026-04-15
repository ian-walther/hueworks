defmodule Hueworks.Circadian.Config do
  @moduledoc """
  Validation and normalization for scene-level circadian settings.

  Key names intentionally mirror Home Assistant Adaptive Lighting calculation
  options, excluding sleep-mode and RGB-related settings.
  """

  use Ecto.Schema

  import Ecto.Changeset

  @brightness_modes [:quadratic, :linear, :tanh]

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

  @supported_keys Enum.map(@supported_key_atoms, &Atom.to_string/1)
  @supported_key_atom_set MapSet.new(@supported_key_atoms)

  @offset_fields [
    :sunrise_offset,
    :sunset_offset,
    :brightness_sunrise_offset,
    :brightness_sunset_offset,
    :temperature_sunrise_offset,
    :temperature_sunset_offset
  ]

  @duration_fields [
    :brightness_mode_time_dark,
    :brightness_mode_time_light
  ]

  @time_fields [
    :sunrise_time,
    :min_sunrise_time,
    :max_sunrise_time,
    :sunset_time,
    :min_sunset_time,
    :max_sunset_time
  ]

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

  embedded_schema do
    field(:min_brightness, :integer)
    field(:max_brightness, :integer)
    field(:min_color_temp, :integer)
    field(:max_color_temp, :integer)
    field(:temperature_ceiling_kelvin, :integer)
    field(:sunrise_time, :string)
    field(:min_sunrise_time, :string)
    field(:max_sunrise_time, :string)
    field(:sunrise_offset, :integer)
    field(:sunset_time, :string)
    field(:min_sunset_time, :string)
    field(:max_sunset_time, :string)
    field(:sunset_offset, :integer)
    field(:brightness_mode, Ecto.Enum, values: @brightness_modes)
    field(:brightness_mode_time_dark, :integer)
    field(:brightness_mode_time_light, :integer)
    field(:brightness_sunrise_offset, :integer)
    field(:brightness_sunset_offset, :integer)
    field(:temperature_sunrise_offset, :integer)
    field(:temperature_sunset_offset, :integer)
  end

  def supported_keys, do: @supported_keys
  def defaults, do: @defaults

  def load(config) when is_map(config) do
    case load_internal(config) do
      {:ok, config_struct, _present_fields} -> {:ok, config_struct}
      {:error, _errors} = error -> error
    end
  end

  def load(_config), do: {:error, [{"config", "must be a map"}]}

  def runtime(config) when is_map(config) do
    config
    |> stringify_keys()
    |> then(&Map.merge(@defaults, &1))
    |> load()
    |> case do
      {:ok, config_struct} -> {:ok, runtime_map(config_struct)}
      {:error, _reason} = error -> error
    end
  end

  def runtime(_config), do: {:error, [{"config", "must be a map"}]}

  def normalize(config) when is_map(config) do
    case load_internal(config) do
      {:ok, config_struct, present_fields} -> {:ok, dump_map(config_struct, present_fields)}
      {:error, _errors} = error -> error
    end
  end

  def normalize(_config), do: {:error, [{"config", "must be a map"}]}

  defp load_internal(config) do
    config
    |> stringify_keys()
    |> prepare_attrs()
    |> case do
      {:ok, attrs, present_fields} ->
        changeset = changeset(%__MODULE__{}, attrs)

        case apply_action(changeset, :validate) do
          {:ok, config_struct} -> {:ok, config_struct, present_fields}
          {:error, changeset} -> {:error, errors_from_changeset(changeset)}
        end

      {:error, _errors} = error ->
        error
    end
  end

  defp changeset(config, attrs) do
    config
    |> cast(attrs, @supported_key_atoms)
    |> validate_number(:min_brightness, greater_than_or_equal_to: 1, less_than_or_equal_to: 100)
    |> validate_number(:max_brightness, greater_than_or_equal_to: 1, less_than_or_equal_to: 100)
    |> validate_number(:min_color_temp,
      greater_than_or_equal_to: 1000,
      less_than_or_equal_to: 10_000
    )
    |> validate_number(:max_color_temp,
      greater_than_or_equal_to: 1000,
      less_than_or_equal_to: 10_000
    )
    |> validate_number(:temperature_ceiling_kelvin,
      greater_than_or_equal_to: 1000,
      less_than_or_equal_to: 10_000
    )
    |> validate_number(:brightness_mode_time_dark, greater_than_or_equal_to: 0)
    |> validate_number(:brightness_mode_time_light, greater_than_or_equal_to: 0)
    |> validate_min_max_order(:min_brightness, :max_brightness)
    |> validate_min_max_order(:min_color_temp, :max_color_temp)
    |> validate_time_order(:min_sunrise_time, :max_sunrise_time)
    |> validate_time_order(:min_sunset_time, :max_sunset_time)
    |> validate_ceiling_order(:temperature_ceiling_kelvin, :min_color_temp, :max_color_temp)
  end

  defp prepare_attrs(config) do
    {attrs, present_fields, errors} =
      Enum.reduce(config, {%{}, MapSet.new(), []}, fn {key, value},
                                                      {attrs, present_fields, errors} ->
        case key_atom(key) do
          nil ->
            {attrs, present_fields, [{key, "is not supported"} | errors]}

          field ->
            case normalize_value(field, value) do
              {:ok, normalized_value} ->
                {
                  Map.put(attrs, field, normalized_value),
                  MapSet.put(present_fields, field),
                  errors
                }

              {:error, reason} ->
                {attrs, present_fields, [{Atom.to_string(field), reason} | errors]}
            end
        end
      end)

    case errors do
      [] -> {:ok, attrs, present_fields}
      _ -> {:error, Enum.reverse(errors)}
    end
  end

  defp normalize_value(:min_brightness, value),
    do: parse_int_in_range(value, 1, 100)

  defp normalize_value(:max_brightness, value),
    do: parse_int_in_range(value, 1, 100)

  defp normalize_value(:min_color_temp, value),
    do: parse_int_in_range(value, 1000, 10_000)

  defp normalize_value(:max_color_temp, value),
    do: parse_int_in_range(value, 1000, 10_000)

  defp normalize_value(:temperature_ceiling_kelvin, value),
    do: parse_int_in_range_or_none(value, 1000, 10_000)

  defp normalize_value(field, value) when field in @offset_fields, do: parse_offset_seconds(value)

  defp normalize_value(field, value) when field in @duration_fields,
    do: parse_non_negative_seconds(value)

  defp normalize_value(field, value) when field in @time_fields, do: parse_time_or_none(value)

  defp normalize_value(:brightness_mode, value) do
    mode =
      case value do
        atom when atom in @brightness_modes -> atom
        string when is_binary(string) -> string |> String.trim() |> existing_atom_or(nil)
        _ -> nil
      end

    if mode in @brightness_modes do
      {:ok, mode}
    else
      {:error, "must be one of: #{Enum.map_join(@brightness_modes, ", ", &Atom.to_string/1)}"}
    end
  end

  defp dump_map(%__MODULE__{} = config, present_fields) do
    Enum.reduce(present_fields, %{}, fn field, acc ->
      Map.put(acc, Atom.to_string(field), dump_value(field, Map.get(config, field)))
    end)
  end

  defp runtime_map(%__MODULE__{} = config) do
    Enum.reduce(@supported_key_atoms, %{}, fn field, acc ->
      Map.put(acc, field, Map.get(config, field))
    end)
  end

  defp dump_value(:brightness_mode, value) when is_atom(value), do: Atom.to_string(value)
  defp dump_value(_field, value), do: value

  defp key_atom(key) when is_binary(key) do
    case existing_atom_or(key) do
      atom when is_atom(atom) ->
        if MapSet.member?(@supported_key_atom_set, atom), do: atom, else: nil

      _ ->
        nil
    end
  end

  defp key_atom(key) when is_atom(key) do
    if MapSet.member?(@supported_key_atom_set, key), do: key, else: nil
  end

  defp key_atom(_key), do: nil

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
      {:ok, time} -> {:ok, Time.to_iso8601(time)}
      {:error, _reason} -> {:error, "must be HH:MM[:SS] or None"}
    end
  end

  defp parse_time_or_none(_value), do: {:error, "must be HH:MM[:SS] or None"}

  defp maybe_expand_hours_minutes(value) do
    if Regex.match?(~r/^\d{1,2}:\d{2}$/, value), do: value <> ":00", else: value
  end

  defp parse_duration_seconds(value) do
    case parse_integer(value) do
      {:ok, seconds} -> {:ok, seconds}
      {:error, _reason} -> parse_hms_duration(value)
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

  defp validate_min_max_order(changeset, min_field, max_field) do
    min = get_field(changeset, min_field)
    max = get_field(changeset, max_field)

    if is_integer(min) and is_integer(max) and min > max do
      changeset
      |> add_error(min_field, "must be less than or equal to #{max_field}")
      |> add_error(max_field, "must be greater than or equal to #{min_field}")
    else
      changeset
    end
  end

  defp validate_time_order(changeset, min_field, max_field) do
    min = get_field(changeset, min_field)
    max = get_field(changeset, max_field)

    with min when is_binary(min) <- min,
         max when is_binary(max) <- max,
         {:ok, min_time} <- Time.from_iso8601(min),
         {:ok, max_time} <- Time.from_iso8601(max),
         :gt <- Time.compare(min_time, max_time) do
      changeset
      |> add_error(min_field, "must be less than or equal to #{max_field}")
      |> add_error(max_field, "must be greater than or equal to #{min_field}")
    else
      _ -> changeset
    end
  end

  defp validate_ceiling_order(changeset, ceiling_field, min_field, max_field) do
    ceiling = get_field(changeset, ceiling_field)
    min_value = get_field(changeset, min_field)
    max_value = get_field(changeset, max_field)

    cond do
      is_nil(ceiling) ->
        changeset

      is_integer(min_value) and ceiling < min_value ->
        add_error(changeset, ceiling_field, "must be greater than or equal to #{min_field}")

      is_integer(max_value) and ceiling > max_value ->
        add_error(changeset, ceiling_field, "must be less than or equal to #{max_field}")

      true ->
        changeset
    end
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

  defp errors_from_changeset(changeset) do
    changeset
    |> traverse_errors(&interpolate_error/1)
    |> Enum.flat_map(fn {field, messages} ->
      Enum.map(messages, fn message -> {Atom.to_string(field), message} end)
    end)
  end

  defp interpolate_error({msg, opts}) do
    Regex.replace(~r/%{(\w+)}/, msg, fn _, key ->
      opts
      |> Keyword.get(String.to_existing_atom(key), key)
      |> to_string()
    end)
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
