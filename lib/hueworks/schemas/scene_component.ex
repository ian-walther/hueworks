defmodule Hueworks.Schemas.SceneComponent do
  use Ecto.Schema
  import Ecto.Changeset

  alias Hueworks.Schemas.LightState.ManualConfig

  schema "scene_components" do
    field(:name, :string)
    field(:metadata, :map, default: %{})
    field(:embedded_manual_config, :map)

    belongs_to(:scene, Hueworks.Schemas.Scene)
    belongs_to(:light_state, Hueworks.Schemas.LightState)
    has_many(:scene_component_lights, Hueworks.Schemas.SceneComponentLight)
    has_many(:lights, through: [:scene_component_lights, :light])

    timestamps()
  end

  def changeset(scene_component, attrs) do
    scene_component
    |> cast(attrs, [:name, :metadata, :scene_id, :light_state_id, :embedded_manual_config])
    |> validate_required([:scene_id])
    |> normalize_embedded_manual_config()
    |> validate_light_state_source()
  end

  defp normalize_embedded_manual_config(changeset) do
    case get_change(changeset, :embedded_manual_config) do
      nil ->
        changeset

      config ->
        case ManualConfig.normalize(config) do
          {:ok, normalized} -> put_change(changeset, :embedded_manual_config, normalized)
          {:error, _errors} -> add_error(changeset, :embedded_manual_config, "is invalid")
        end
    end
  end

  defp validate_light_state_source(changeset) do
    light_state_id = get_field(changeset, :light_state_id)
    embedded_manual_config = get_field(changeset, :embedded_manual_config)

    cond do
      is_integer(light_state_id) and is_map(embedded_manual_config) ->
        changeset
        |> add_error(:light_state_id, "cannot be used with embedded manual config")
        |> add_error(:embedded_manual_config, "cannot be used with a saved light state")

      is_integer(light_state_id) ->
        changeset

      is_map(embedded_manual_config) ->
        changeset

      true ->
        add_error(changeset, :light_state_id, "or embedded manual config must be present")
    end
  end
end
