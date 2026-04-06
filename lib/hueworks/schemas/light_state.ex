defmodule Hueworks.Schemas.LightState do
  use Ecto.Schema
  import Ecto.Changeset

  alias Hueworks.Circadian.Config, as: CircadianConfig
  alias Hueworks.Util

  @manual_modes ["temperature", "color"]
  schema "light_states" do
    field(:name, :string)
    field(:type, Ecto.Enum, values: [:manual, :circadian])
    field(:config, :map, default: %{})

    has_many(:scene_components, Hueworks.Schemas.SceneComponent)

    timestamps()
  end

  def changeset(light_state, attrs) do
    light_state
    |> cast(attrs, [:name, :type, :config])
    |> validate_required([:name, :type])
    |> validate_type_config()
  end

  defp validate_type_config(changeset) do
    case get_field(changeset, :type) do
      :manual ->
        validate_manual_config(changeset)

      :circadian ->
        validate_circadian_config(changeset)

      _ ->
        changeset
    end
  end

  defp validate_circadian_config(changeset) do
    config = get_field(changeset, :config) || %{}

    case CircadianConfig.normalize(config) do
      {:ok, normalized} ->
        put_change(changeset, :config, normalized)

      {:error, errors} ->
        Enum.reduce(errors, changeset, fn {key, message}, acc ->
          add_error(acc, :config, "#{key} #{message}")
        end)
    end
  end

  defp validate_manual_config(changeset) do
    config = get_field(changeset, :config) || %{}
    normalized = normalize_config_keys(config)
    mode = Map.get(normalized, "mode", "temperature")

    changeset =
      if mode in @manual_modes do
        put_change(changeset, :config, Map.put(normalized, "mode", mode))
      else
        add_error(changeset, :config, "mode is invalid")
      end

    Enum.reduce(["brightness", "temperature", "kelvin", "hue", "saturation"], changeset, fn key,
                                                                                            acc ->
      normalize_manual_field(acc, key)
    end)
  end

  defp normalize_manual_field(changeset, key) do
    config = get_field(changeset, :config) || %{}

    case Map.fetch(config, key) do
      :error ->
        changeset

      {:ok, value} ->
        case normalize_optional_numeric(value, key) do
          {:ok, nil} ->
            put_change(changeset, :config, Map.delete(config, key))

          {:ok, normalized} ->
            put_change(changeset, :config, Map.put(config, key, normalized))

          :error ->
            add_error(changeset, :config, "#{key} is invalid")
        end
    end
  end

  defp normalize_optional_numeric(nil, _normalizer), do: {:ok, nil}

  defp normalize_optional_numeric(value, key) do
    case normalize_manual_numeric(value, key) do
      nil ->
        if value in ["", nil] do
          {:ok, nil}
        else
          :error
        end

      normalized ->
        {:ok, normalized}
    end
  end

  defp normalize_manual_numeric(value, "brightness"), do: Util.normalize_percent(value)

  defp normalize_manual_numeric(value, "temperature"),
    do: Util.normalize_kelvin_value(value, 1000, 10000)

  defp normalize_manual_numeric(value, "kelvin"),
    do: Util.normalize_kelvin_value(value, 1000, 10000)

  defp normalize_manual_numeric(value, "hue"), do: Util.normalize_hue_degrees(value)
  defp normalize_manual_numeric(value, "saturation"), do: Util.normalize_saturation(value)
  defp normalize_manual_numeric(_value, _key), do: nil

  defp normalize_config_keys(config) when is_map(config) do
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

  defp normalize_config_keys(_config), do: %{}
end
