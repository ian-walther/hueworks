defmodule Hueworks.HomeAssistant.Export.Entities do
  @moduledoc false

  import Ecto.Query, only: [from: 2]

  alias Hueworks.Groups
  alias Hueworks.HomeAssistant.Export.Messages
  alias Hueworks.HomeAssistant.Export.Messages.RoomSceneOption
  alias Hueworks.Repo
  alias Hueworks.Schemas.{Group, Light, Room, Scene}

  def control_target(:light, light_id) when is_integer(light_id) do
    case fetch_entity(:light, light_id) do
      %Light{} = light -> {light.room_id, [light.id]}
      _ -> nil
    end
  end

  def control_target(:group, group_id) when is_integer(group_id) do
    case fetch_entity(:group, group_id) do
      %Group{} = group ->
        light_ids = Groups.member_light_ids(group.id)
        {group.room_id, light_ids}

      _ ->
        nil
    end
  end

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

  def list_exportable_scenes do
    Repo.all(
      from(s in Scene,
        join: r in Room,
        on: r.id == s.room_id,
        preload: [room: r],
        order_by: [asc: r.name, asc: s.name]
      )
    )
  end

  def list_rooms do
    Repo.all(from(r in Room, order_by: [asc: r.name]))
  end

  def list_exportable_scenes_for_room(room_id) when is_integer(room_id) do
    Repo.all(
      from(s in Scene,
        join: r in Room,
        on: r.id == s.room_id,
        where: s.room_id == ^room_id,
        preload: [room: r],
        order_by: [asc: s.name]
      )
    )
  end

  def exportable_scene(scene_id) when is_integer(scene_id) do
    Repo.one(
      from(s in Scene,
        join: r in Room,
        on: r.id == s.room_id,
        where: s.id == ^scene_id,
        preload: [room: r]
      )
    )
  end

  def scene_for_room_option(room_id, option_label)
      when is_integer(room_id) and is_binary(option_label) do
    room_id
    |> list_exportable_scenes_for_room()
    |> Messages.room_scene_options()
    |> Enum.find_value(fn %RoomSceneOption{label: label, scene: scene} ->
      if label == option_label, do: scene, else: nil
    end)
  end

  def scene_for_room_option(_room_id, _option_label), do: nil

  def list_exportable_lights do
    Repo.all(
      from(l in Light,
        where: is_nil(l.canonical_light_id) and l.enabled == true and l.ha_export_mode != :none,
        order_by: [asc: l.name]
      )
    )
    |> Repo.preload(:room)
  end

  def list_exportable_groups do
    Repo.all(
      from(g in Group,
        where: is_nil(g.canonical_group_id) and g.enabled == true and g.ha_export_mode != :none,
        order_by: [asc: g.name]
      )
    )
    |> Repo.preload([:room, :lights])
  end

  def list_exportable_lights_for_room(room_id) when is_integer(room_id) do
    Repo.all(
      from(l in Light,
        where:
          l.room_id == ^room_id and is_nil(l.canonical_light_id) and l.enabled == true and
            l.ha_export_mode != :none,
        order_by: [asc: l.name]
      )
    )
    |> Repo.preload(:room)
  end

  def list_exportable_groups_for_room(room_id) when is_integer(room_id) do
    Repo.all(
      from(g in Group,
        where:
          g.room_id == ^room_id and is_nil(g.canonical_group_id) and g.enabled == true and
            g.ha_export_mode != :none,
        order_by: [asc: g.name]
      )
    )
    |> Repo.preload([:room, :lights])
  end

  def list_controllable_light_ids do
    Repo.all(
      from(l in Light,
        where: is_nil(l.canonical_light_id),
        select: l.id
      )
    )
  end

  def list_controllable_group_ids do
    Repo.all(
      from(g in Group,
        where: is_nil(g.canonical_group_id),
        select: g.id
      )
    )
  end
end
