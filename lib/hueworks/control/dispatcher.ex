defmodule Hueworks.Control.Dispatcher do
  @moduledoc """
  Plans optimized control actions from desired state diffs.
  """

  import Ecto.Query, only: [from: 2]

  alias Hueworks.Control.DesiredState
  alias Hueworks.Repo
  alias Hueworks.Schemas.{Group, GroupLight, Light}

  def plan_room(room_id, diff) when is_integer(room_id) and is_map(diff) do
    room_lights =
      Repo.all(
        from(l in Light,
          where: l.room_id == ^room_id,
          select: %{id: l.id, bridge_id: l.bridge_id}
        )
      )

    room_light_ids = MapSet.new(Enum.map(room_lights, & &1.id))

    desired_by_light =
      Map.new(room_lights, fn light ->
        {light.id, DesiredState.get(:light, light.id)}
      end)

    diff_light_ids =
      diff
      |> Map.keys()
      |> Enum.flat_map(fn
        {:light, id} when is_integer(id) -> [id]
        {"light", id} when is_integer(id) -> [id]
        _ -> []
      end)
      |> Enum.filter(&MapSet.member?(room_light_ids, &1))

    group_memberships = load_group_memberships(room_id)

    diff_light_ids
    |> Enum.group_by(fn id ->
      desired = Map.get(desired_by_light, id) || %{}
      {desired_key(desired), desired, light_bridge(room_lights, id)}
    end)
    |> Enum.flat_map(fn {{_key, desired, bridge_id}, ids} ->
      candidate_ids =
        room_lights
        |> Enum.filter(fn light ->
          light.bridge_id == bridge_id and
            desired_key(Map.get(desired_by_light, light.id) || %{}) == desired_key(desired)
        end)
        |> Enum.map(& &1.id)
        |> MapSet.new()

      groups = Enum.filter(group_memberships, &(&1.bridge_id == bridge_id))
      {group_actions, remaining} = plan_groups(groups, candidate_ids, MapSet.new(ids), desired)
      group_actions ++ plan_lights(remaining, bridge_id, desired)
    end)
  end

  defp light_bridge(room_lights, id) do
    case Enum.find(room_lights, &(&1.id == id)) do
      nil -> nil
      %{bridge_id: bridge_id} -> bridge_id
    end
  end

  defp load_group_memberships(room_id) do
    groups =
      Repo.all(
        from(g in Group,
          where: g.room_id == ^room_id,
          select: %{id: g.id, bridge_id: g.bridge_id}
        )
      )

    memberships =
      Repo.all(
        from(gl in GroupLight,
          join: g in Group,
          on: g.id == gl.group_id,
          where: g.room_id == ^room_id,
          select: {g.id, gl.light_id}
        )
      )

    base =
      Enum.map(groups, fn group ->
        %{id: group.id, bridge_id: group.bridge_id, lights: MapSet.new()}
      end)

    Enum.reduce(memberships, base, fn {group_id, light_id}, acc ->
      Enum.map(acc, fn group ->
        if group.id == group_id do
          %{group | lights: MapSet.put(group.lights, light_id)}
        else
          group
        end
      end)
    end)
  end

  defp plan_groups(groups, candidate_set, remaining_diff, desired) do
    case pick_group(groups, candidate_set, remaining_diff) do
      nil ->
        {[], remaining_diff}

      group ->
        updated_remaining = MapSet.difference(remaining_diff, group.lights)
        {rest, final_remaining} =
          plan_groups(groups, candidate_set, updated_remaining, desired)

        {[%{type: :group, id: group.id, bridge_id: group.bridge_id, desired: desired} | rest],
         final_remaining}
    end
  end

  defp pick_group(groups, candidate_set, remaining_diff) do
    groups
    |> Enum.filter(fn group ->
      MapSet.size(group.lights) > 0 and MapSet.subset?(group.lights, candidate_set) and
        not MapSet.disjoint?(group.lights, remaining_diff)
    end)
    |> Enum.sort_by(fn group -> -MapSet.size(group.lights) end)
    |> List.first()
  end

  defp plan_lights(remaining_diff, bridge_id, desired) do
    remaining_diff
    |> MapSet.to_list()
    |> Enum.map(fn id ->
      %{type: :light, id: id, bridge_id: bridge_id, desired: desired}
    end)
  end

  defp desired_key(desired) when is_map(desired) do
    desired
    |> Map.to_list()
    |> Enum.sort()
  end
end
