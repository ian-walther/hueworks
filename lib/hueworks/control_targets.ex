defmodule Hueworks.ControlTargets do
  @moduledoc false

  import Ecto.Query, only: [from: 2]

  alias Hueworks.Groups
  alias Hueworks.Repo
  alias Hueworks.Schemas.{Group, Light}

  def fetch_entity(:light, light_id) when is_integer(light_id) do
    Repo.one(
      from(l in Light,
        where: l.id == ^light_id and is_nil(l.canonical_light_id)
      )
    )
    |> Repo.preload(:room)
  end

  def fetch_entity(:group, group_id) when is_integer(group_id) do
    Repo.one(
      from(g in Group,
        where: g.id == ^group_id and is_nil(g.canonical_group_id)
      )
    )
    |> Repo.preload([:room, :lights])
  end

  def fetch_entity(_kind, _id), do: nil

  def control_target(:light, light_id) when is_integer(light_id) do
    case fetch_entity(:light, light_id) do
      %Light{} = light -> {light.room_id, [light.id]}
      _ -> nil
    end
  end

  def control_target(:group, group_id) when is_integer(group_id) do
    case fetch_entity(:group, group_id) do
      %Group{} = group -> {group.room_id, Groups.member_light_ids(group.id)}
      _ -> nil
    end
  end

  def control_target(_kind, _id), do: nil
end
