defmodule Hueworks.Schemas.SceneComponentLight do
  use Ecto.Schema
  import Ecto.Changeset

  alias Hueworks.Scenes.PowerPolicy

  @power_policy_values PowerPolicy.values()

  schema "scene_component_lights" do
    field(:default_power, Ecto.Enum,
      values: @power_policy_values,
      default: :default_on
    )

    belongs_to(:scene_component, Hueworks.Schemas.SceneComponent)
    belongs_to(:light, Hueworks.Schemas.Light)
    belongs_to(:presence_input, Hueworks.Schemas.PresenceInput)

    timestamps()
  end

  def changeset(scene_component_light, attrs) do
    scene_component_light
    |> cast(attrs, [:scene_component_id, :light_id, :default_power, :presence_input_id])
    |> validate_required([:scene_component_id, :light_id, :default_power])
    |> validate_presence_input_for_policy()
    |> unique_constraint([:scene_component_id, :light_id])
  end

  defp validate_presence_input_for_policy(changeset) do
    case get_field(changeset, :default_power) do
      :follow_presence ->
        validate_required(changeset, [:presence_input_id])

      _policy ->
        put_change(changeset, :presence_input_id, nil)
    end
  end
end
