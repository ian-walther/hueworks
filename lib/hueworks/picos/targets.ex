defmodule Hueworks.Picos.Targets do
  @moduledoc false

  import Ecto.Query, only: [from: 2]

  alias Hueworks.Groups
  alias Hueworks.Repo
  alias Hueworks.Scenes
  alias Hueworks.Schemas.{Group, Light, Scene}

  def expand_room_targets(room_id, group_ids, light_ids) do
    allowed_light_ids =
      Repo.all(
        from(l in Light,
          where: l.room_id == ^room_id and is_nil(l.canonical_light_id),
          select: l.id
        )
      )
      |> MapSet.new()

    group_light_ids =
      group_ids
      |> normalize_integer_ids()
      |> Enum.flat_map(fn group_id ->
        case Repo.one(from(g in Group, where: g.id == ^group_id, select: g.room_id)) do
          ^room_id -> Groups.member_light_ids(group_id)
          _ -> []
        end
      end)

    direct_light_ids =
      light_ids
      |> normalize_integer_ids()
      |> Enum.filter(&MapSet.member?(allowed_light_ids, &1))

    (group_light_ids ++ direct_light_ids)
    |> Enum.filter(&MapSet.member?(allowed_light_ids, &1))
    |> Enum.uniq()
  end

  def valid_room_targets?(room_id, group_ids, light_ids) do
    allowed_light_ids =
      Repo.all(
        from(l in Light,
          where: l.room_id == ^room_id and is_nil(l.canonical_light_id),
          select: l.id
        )
      )
      |> MapSet.new()

    allowed_group_ids =
      Repo.all(
        from(g in Group,
          where: g.room_id == ^room_id and is_nil(g.canonical_group_id),
          select: g.id
        )
      )
      |> MapSet.new()

    Enum.all?(group_ids, &MapSet.member?(allowed_group_ids, &1)) and
      Enum.all?(light_ids, &MapSet.member?(allowed_light_ids, &1))
  end

  def control_group_light_ids(room_id, %{"group_ids" => group_ids, "light_ids" => light_ids}) do
    expand_room_targets(room_id, group_ids, light_ids)
  end

  def control_group_light_ids(_room_id, _group), do: []

  def normalize_integer_ids(values) do
    values
    |> List.wrap()
    |> Enum.flat_map(fn
      value when is_integer(value) ->
        [value]

      value when is_binary(value) ->
        case Integer.parse(value) do
          {parsed, ""} -> [parsed]
          _ -> []
        end

      _ ->
        []
    end)
    |> Enum.uniq()
  end

  def scene_exists_in_room?(room_id, scene_id)
      when is_integer(room_id) and is_integer(scene_id) do
    Repo.exists?(from(s in Scene, where: s.room_id == ^room_id and s.id == ^scene_id))
  end

  def scene_exists_in_room?(_room_id, _scene_id), do: false

  def scene_name_for_target(scene_id, room_id)
      when is_integer(scene_id) and is_integer(room_id) do
    room_id
    |> Scenes.list_scenes_for_room()
    |> Enum.find_value("Unknown Scene", fn scene ->
      if scene.id == scene_id, do: scene.name, else: nil
    end)
  end

  def scene_name_for_target(_scene_id, _room_id), do: "Unknown Scene"
end
