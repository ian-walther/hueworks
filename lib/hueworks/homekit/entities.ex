defmodule Hueworks.HomeKit.Entities do
  @moduledoc false

  import Ecto.Query, only: [from: 2]

  alias Hueworks.Groups
  alias Hueworks.Repo
  alias Hueworks.Schemas.{Group, Light, Room, Scene}

  def list_exposed_lights do
    Repo.all(
      from(l in Light,
        where:
          is_nil(l.canonical_light_id) and l.enabled == true and
            l.homekit_export_mode != :none,
        order_by: [asc: l.name, asc: l.id]
      )
    )
    |> Repo.preload(:room)
  end

  def list_exposed_groups do
    Repo.all(
      from(g in Group,
        where:
          is_nil(g.canonical_group_id) and g.enabled == true and
            g.homekit_export_mode != :none,
        order_by: [asc: g.name, asc: g.id]
      )
    )
    |> Repo.preload([:room, :lights])
  end

  def list_scenes do
    Repo.all(
      from(s in Scene,
        join: r in Room,
        on: r.id == s.room_id,
        preload: [room: r],
        order_by: [asc: r.name, asc: s.name, asc: s.id]
      )
    )
  end

  def fetch_entity(:light, id) when is_integer(id) do
    Repo.one(
      from(l in Light,
        where: l.id == ^id and is_nil(l.canonical_light_id)
      )
    )
    |> Repo.preload(:room)
  end

  def fetch_entity(:group, id) when is_integer(id) do
    Repo.one(
      from(g in Group,
        where: g.id == ^id and is_nil(g.canonical_group_id)
      )
    )
    |> Repo.preload([:room, :lights])
  end

  def fetch_entity(_kind, _id), do: nil

  def control_target(:light, id) when is_integer(id) do
    case fetch_entity(:light, id) do
      %Light{} = light -> {light.room_id, [light.id]}
      _ -> nil
    end
  end

  def control_target(:group, id) when is_integer(id) do
    case fetch_entity(:group, id) do
      %Group{} = group -> {group.room_id, Groups.member_light_ids(group.id)}
      _ -> nil
    end
  end

  def control_target(_kind, _id), do: nil

  def fetch_scene(id) when is_integer(id) do
    Repo.get(Scene, id)
    |> Repo.preload(:room)
  end

  def fetch_scene(_id), do: nil
end
