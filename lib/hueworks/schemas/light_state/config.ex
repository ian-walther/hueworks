defmodule Hueworks.Schemas.LightState.Config do
  use Ecto.Schema

  import Ecto.Changeset

  alias Hueworks.Circadian.Config, as: CircadianConfig
  alias Hueworks.Schemas.LightState.ManualConfig

  @circadian_fields [
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

  @primary_key false
  @primary_key false
  embedded_schema do
    field(:mode, Ecto.Enum, values: [:temperature, :color], default: :temperature)
    field(:brightness, :integer)
    field(:temperature, :integer)
    field(:hue, :integer)
    field(:saturation, :integer)

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
    field(:brightness_mode, Ecto.Enum, values: [:quadratic, :linear, :tanh])
    field(:brightness_mode_time_dark, :integer)
    field(:brightness_mode_time_light, :integer)
    field(:brightness_sunrise_offset, :integer)
    field(:brightness_sunset_offset, :integer)
    field(:temperature_sunrise_offset, :integer)
    field(:temperature_sunset_offset, :integer)
  end

  def manual_changeset(config, attrs) when is_map(attrs) do
    config
    |> to_manual_config()
    |> ManualConfig.changeset(attrs)
    |> apply_embedded_result(&from_manual_config/1)
  end

  def manual_changeset(config, _attrs), do: manual_changeset(config, %{})

  def circadian_changeset(config, attrs) when is_map(attrs) do
    config
    |> persisted_config(:circadian)
    |> Map.merge(stringify_keys(attrs))
    |> CircadianConfig.load()
    |> case do
      {:ok, config} ->
        config
        |> from_circadian_config()
        |> Map.from_struct()
        |> Enum.reject(fn {_key, value} -> is_nil(value) end)
        |> Map.new()
        |> then(&change(%__MODULE__{}, &1))

      {:error, errors} ->
        Enum.reduce(errors, change(%__MODULE__{}), fn {field, message}, acc ->
          case existing_atom_or(field) do
            atom when is_atom(atom) -> add_error(acc, atom, message)
            _ -> add_error(acc, :base, "#{field} #{message}")
          end
        end)
    end
  end

  def circadian_changeset(config, _attrs), do: circadian_changeset(config, %{})

  def manual_mode(%__MODULE__{} = config), do: config.mode || :temperature
  def manual_mode(_config), do: :temperature

  def manual_map(%__MODULE__{} = config) do
    config
    |> to_manual_config()
    |> ManualConfig.canonical_map()
  end

  def manual_map(config), do: config |> to_manual_config() |> ManualConfig.canonical_map()

  def circadian_struct(%__MODULE__{} = config), do: to_circadian_config(config)
  def circadian_struct(config), do: config |> to_circadian_config()

  def persisted_config(%__MODULE__{} = config, :manual) do
    config
    |> to_manual_config()
    |> ManualConfig.dump()
  end

  def persisted_config(%__MODULE__{} = config, :circadian) do
    config
    |> to_circadian_config()
    |> CircadianConfig.dump()
  end

  def persisted_config(config, type) when is_map(config) do
    case type do
      :manual ->
        config
        |> to_manual_config()
        |> ManualConfig.dump()

      :circadian ->
        config
        |> to_circadian_config()
        |> CircadianConfig.dump()

      _ ->
        stringify_keys(config)
    end
  end

  defp stringify_keys(attrs) do
    Enum.into(attrs, %{}, fn {key, value} ->
      normalized_key =
        case key do
          atom when is_atom(atom) -> Atom.to_string(atom)
          binary when is_binary(binary) -> binary
          other -> to_string(other)
        end

      {normalized_key, value}
    end)
  end

  defp existing_atom_or(value) when is_atom(value), do: value

  defp existing_atom_or(value) when is_binary(value) do
    try do
      String.to_existing_atom(value)
    rescue
      ArgumentError -> nil
    end
  end

  defp existing_atom_or(_value), do: nil

  defp apply_embedded_result(changeset, converter) do
    case apply_action(changeset, :validate) do
      {:ok, config} ->
        config
        |> converter.()
        |> Map.from_struct()
        |> Enum.reject(fn {_key, value} -> is_nil(value) end)
        |> Map.new()
        |> then(&change(%__MODULE__{}, &1))

      {:error, changeset} ->
        Enum.reduce(changeset.errors, change(%__MODULE__{}), fn {field, {message, opts}}, acc ->
          add_error(acc, field, message, opts)
        end)
    end
  end

  defp to_manual_config(%__MODULE__{} = config) do
    %ManualConfig{
      mode: config.mode,
      brightness: config.brightness,
      temperature: config.temperature,
      hue: config.hue,
      saturation: config.saturation
    }
  end

  defp to_manual_config(config) when is_map(config), do: ManualConfig.load(config)
  defp to_manual_config(_config), do: %ManualConfig{}

  defp from_manual_config(%ManualConfig{} = config) do
    %__MODULE__{
      mode: config.mode,
      brightness: config.brightness,
      temperature: config.temperature,
      hue: config.hue,
      saturation: config.saturation
    }
  end

  defp to_circadian_config(%__MODULE__{} = config) do
    CircadianConfig.__schema__(:fields)
    |> Enum.reduce(%CircadianConfig{}, fn field, acc ->
      Map.put(acc, field, Map.get(config, field))
    end)
  end

  defp to_circadian_config(%CircadianConfig{} = config), do: config

  defp to_circadian_config(config) when is_map(config) do
    case CircadianConfig.load(config) do
      {:ok, circadian_config} -> circadian_config
      {:error, _errors} -> %CircadianConfig{}
    end
  end

  defp to_circadian_config(_config), do: %CircadianConfig{}

  defp from_circadian_config(%CircadianConfig{} = config) do
    fields = @circadian_fields

    Enum.reduce(fields, %__MODULE__{}, fn field, acc ->
      Map.put(acc, field, Map.get(config, field))
    end)
  end
end
