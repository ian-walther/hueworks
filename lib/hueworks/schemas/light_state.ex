defmodule Hueworks.Schemas.LightState do
  use Ecto.Schema
  import Ecto.Changeset

  schema "light_states" do
    field(:name, :string)
    field(:type, Ecto.Enum, values: [:off, :manual, :circadian])
    field(:config, :map, default: %{})

    has_many(:scene_components, Hueworks.Schemas.SceneComponent)

    timestamps()
  end

  def changeset(light_state, attrs) do
    light_state
    |> cast(attrs, [:name, :type, :config])
    |> validate_required([:name, :type])
  end
end
