defmodule Hueworks.Schemas.GroupLight do
  use Ecto.Schema
  import Ecto.Changeset

  schema "group_lights" do
    belongs_to(:group, Hueworks.Schemas.Group)
    belongs_to(:light, Hueworks.Schemas.Light)

    timestamps()
  end

  def changeset(group_light, attrs) do
    group_light
    |> cast(attrs, [:group_id, :light_id])
    |> validate_required([:group_id, :light_id])
    |> unique_constraint([:group_id, :light_id])
  end
end
