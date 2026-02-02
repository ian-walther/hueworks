defmodule Hueworks.Scenes.Builder do
  @moduledoc false

  def build(room_lights, groups, components) do
    filtered_lights = filter_canonical_lights(room_lights)
    filtered_groups = filter_canonical_groups(groups)
    room_light_ids = light_ids(filtered_lights)

    assigned_ids =
      assigned_light_ids(components) |> MapSet.intersection(MapSet.new(room_light_ids))

    available_lights = available_lights(filtered_lights, assigned_ids)
    available_groups = available_groups(filtered_groups, assigned_ids)
    duplicate_ids = duplicate_light_ids(components, room_light_ids)

    %{
      room_light_ids: room_light_ids,
      assigned_light_ids: assigned_ids,
      available_lights: available_lights,
      available_groups: available_groups,
      unassigned_light_ids: unassigned_light_ids(room_light_ids, assigned_ids),
      duplicate_light_ids: duplicate_ids,
      valid?: valid?(room_light_ids, assigned_ids, duplicate_ids)
    }
  end

  def assigned_light_ids(components) do
    components
    |> Enum.flat_map(&Map.get(&1, :light_ids, []))
    |> Enum.filter(&is_integer/1)
    |> MapSet.new()
  end

  def duplicate_light_ids(components, room_light_ids) do
    room_light_ids = MapSet.new(room_light_ids)

    components
    |> Enum.flat_map(&Map.get(&1, :light_ids, []))
    |> Enum.filter(&is_integer/1)
    |> Enum.filter(&MapSet.member?(room_light_ids, &1))
    |> Enum.frequencies()
    |> Enum.filter(fn {_id, count} -> count > 1 end)
    |> Enum.map(fn {id, _count} -> id end)
    |> Enum.sort()
  end

  def available_lights(room_lights, assigned_ids) do
    Enum.filter(room_lights, fn light ->
      id = Map.get(light, :id)
      is_integer(id) and not MapSet.member?(assigned_ids, id)
    end)
  end

  def available_groups(groups, assigned_ids) do
    groups
    |> Enum.filter(fn group ->
      light_ids = Map.get(group, :light_ids, [])
      light_ids != [] and Enum.all?(light_ids, fn id -> not MapSet.member?(assigned_ids, id) end)
    end)
  end

  defp light_ids(lights) do
    lights
    |> Enum.map(&Map.get(&1, :id))
    |> Enum.filter(&is_integer/1)
  end

  defp unassigned_light_ids(room_light_ids, assigned_ids) do
    room_light_ids
    |> Enum.reject(&MapSet.member?(assigned_ids, &1))
  end

  defp valid?(room_light_ids, assigned_ids, duplicate_ids) do
    duplicate_ids == [] and
      MapSet.new(room_light_ids) == assigned_ids
  end

  defp filter_canonical_lights(lights) do
    Enum.reject(lights, fn light ->
      Map.get(light, :canonical_light_id)
    end)
  end

  defp filter_canonical_groups(groups) do
    Enum.reject(groups, fn group ->
      Map.get(group, :canonical_group_id)
    end)
  end
end
