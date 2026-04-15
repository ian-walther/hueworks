defmodule Hueworks.Schemas.LightState do
  use Ecto.Schema
  import Ecto.Changeset

  alias Hueworks.Circadian.Config, as: CircadianConfig
  alias Hueworks.Schemas.LightState.ManualConfig

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

  def manual_config(%__MODULE__{config: config}), do: manual_config(config)
  def manual_config(config), do: ManualConfig.canonical_map(config)

  def manual_mode(%__MODULE__{} = light_state), do: manual_mode(light_state.config)
  def manual_mode(config), do: ManualConfig.mode(config)

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

    case ManualConfig.normalize(config) do
      {:ok, normalized} ->
        put_change(changeset, :config, normalized)

      {:error, errors} ->
        Enum.reduce(errors, changeset, fn {key, message}, acc ->
          add_error(acc, :config, "#{key} #{message}")
        end)
    end
  end
end
