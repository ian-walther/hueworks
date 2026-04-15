defmodule Hueworks.Schemas.LightState.ManualConfig do
  use Ecto.Schema
  import Ecto.Changeset

  alias Hueworks.Util

  @primary_key false
  embedded_schema do
    field(:mode, Ecto.Enum, values: [:temperature, :color], default: :temperature)
    field(:brightness, :integer)
    field(:temperature, :integer)
    field(:hue, :integer)
    field(:saturation, :integer)
  end

  @fields [:mode, :brightness, :temperature, :hue, :saturation]

  def load(%__MODULE__{} = config), do: config

  def load(attrs) when is_map(attrs) do
    attrs
    |> changeset()
    |> apply_action(:validate)
    |> case do
      {:ok, config} -> config
      {:error, _changeset} -> %__MODULE__{}
    end
  end

  def load(_attrs), do: %__MODULE__{}

  def mode(config) do
    config
    |> load()
    |> Map.get(:mode, :temperature)
  end

  def canonical_map(config) do
    config = load(config)

    %{}
    |> Map.put(:mode, config.mode || :temperature)
    |> maybe_put(:brightness, config.brightness)
    |> maybe_put(:kelvin, config.temperature)
    |> maybe_put(:hue, config.hue)
    |> maybe_put(:saturation, config.saturation)
  end

  def normalize(attrs) when is_map(attrs) do
    passthrough = passthrough_keys(attrs)

    attrs
    |> changeset()
    |> apply_action(:validate)
    |> case do
      {:ok, config} ->
        {:ok, Map.merge(passthrough, dump(config))}

      {:error, changeset} ->
        {:error, changeset_errors(changeset)}
    end
  end

  def normalize(_attrs), do: {:error, [{"config", "must be a map"}]}

  def changeset(attrs), do: changeset(%__MODULE__{}, attrs)

  def changeset(config, attrs) when is_map(attrs) do
    attrs = normalize_input_keys(attrs)

    config
    |> cast(attrs, @fields)
    |> ensure_default_mode()
    |> clamp_numeric(:brightness, &Util.normalize_percent/1)
    |> clamp_numeric(:temperature, &Util.normalize_kelvin_value(&1, 1000, 10_000))
    |> clamp_numeric(:hue, &Util.normalize_hue_degrees/1)
    |> clamp_numeric(:saturation, &Util.normalize_saturation/1)
  end

  def changeset(config, _attrs), do: changeset(config, %{})

  defp dump(%__MODULE__{} = config) do
    %{}
    |> Map.put("mode", Atom.to_string(config.mode || :temperature))
    |> maybe_put_dump("brightness", config.brightness)
    |> maybe_put_dump("temperature", config.temperature)
    |> maybe_put_dump("hue", config.hue)
    |> maybe_put_dump("saturation", config.saturation)
  end

  defp passthrough_keys(attrs) do
    attrs
    |> normalize_input_keys()
    |> Map.drop(["mode", "brightness", "temperature", "kelvin", "hue", "saturation"])
  end

  defp normalize_input_keys(attrs) do
    Enum.into(attrs, %{}, fn {key, value} ->
      normalized_key =
        case key do
          :kelvin -> "temperature"
          "kelvin" -> "temperature"
          atom when is_atom(atom) -> Atom.to_string(atom)
          binary when is_binary(binary) -> binary
          other -> to_string(other)
        end

      {normalized_key, value}
    end)
  end

  defp ensure_default_mode(changeset) do
    case get_field(changeset, :mode) do
      nil -> put_change(changeset, :mode, :temperature)
      _ -> changeset
    end
  end

  defp clamp_numeric(changeset, field, normalizer) do
    update_change(changeset, field, fn value -> normalizer.(value) end)
  end

  defp changeset_errors(changeset) do
    traverse_errors(changeset, fn {message, opts} ->
      Enum.reduce(opts, message, fn {key, value}, acc ->
        String.replace(acc, "%{#{key}}", to_string(value))
      end)
    end)
    |> Enum.flat_map(fn {field, messages} ->
      Enum.map(List.wrap(messages), fn message -> {Atom.to_string(field), message} end)
    end)
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp maybe_put_dump(map, _key, nil), do: map
  defp maybe_put_dump(map, key, value), do: Map.put(map, key, value)
end
