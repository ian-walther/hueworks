defmodule Hueworks.Control.Planner do
  @moduledoc """
  Plans optimized control actions from desired state diffs.
  """

  import Ecto.Query, only: [from: 2]
  require Logger

  alias Hueworks.DebugLogging
  alias Hueworks.Control.LightStateSemantics
  alias Hueworks.Control.RoomSnapshot
  alias Hueworks.Repo
  alias Hueworks.Schemas.Light
  @brightness_tolerance 2
  @temperature_physical_mired_tolerance 1

  def plan_room(room_id, diff, opts \\ []) when is_integer(room_id) and is_map(diff) do
    room_id
    |> RoomSnapshot.load()
    |> plan_snapshot(diff, opts)
  end

  def plan_direct(diff) when is_map(diff) do
    light_ids =
      diff
      |> Map.keys()
      |> Enum.flat_map(fn
        {:light, id} when is_integer(id) -> [id]
        {"light", id} when is_integer(id) -> [id]
        _ -> []
      end)
      |> Enum.uniq()

    bridge_by_light_id =
      Repo.all(
        from(l in Light,
          where: l.id in ^light_ids,
          select: {l.id, l.bridge_id}
        )
      )
      |> Map.new()

    diff
    |> Enum.flat_map(fn
      {{:light, id}, desired} when is_integer(id) and is_map(desired) ->
        case Map.get(bridge_by_light_id, id) do
          nil -> []
          bridge_id -> [%{type: :light, id: id, bridge_id: bridge_id, desired: desired}]
        end

      {{"light", id}, desired} when is_integer(id) and is_map(desired) ->
        case Map.get(bridge_by_light_id, id) do
          nil -> []
          bridge_id -> [%{type: :light, id: id, bridge_id: bridge_id, desired: desired}]
        end

      _ ->
        []
    end)
  end

  def plan_snapshot(snapshot, diff, opts \\ []) when is_map(snapshot) and is_map(diff) do
    trace = Keyword.get(opts, :trace)
    room_id = Map.get(snapshot, :room_id)
    room_lights = Map.get(snapshot, :room_lights, [])
    desired_by_light = Map.get(snapshot, :desired_by_light, %{})
    physical_by_light = Map.get(snapshot, :physical_by_light, %{})
    group_memberships = Map.get(snapshot, :group_memberships, [])

    room_light_ids = MapSet.new(Enum.map(room_lights, & &1.id))

    effective_desired_by_light =
      Map.new(room_lights, fn light ->
        desired = Map.get(desired_by_light, light.id) || %{}
        {light.id, effective_desired_for_light(desired, light)}
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

    actionable_diff_light_ids =
      Enum.filter(diff_light_ids, fn id ->
        desired = Map.get(effective_desired_by_light, id) || %{}
        physical = Map.get(physical_by_light, id, %{})
        desired_differs_from_physical?(desired, physical)
      end)

    log_trace(trace, "planner_input",
      room_id: room_id,
      room_light_count: length(room_lights),
      diff_light_ids: Enum.sort(diff_light_ids),
      actionable_diff_light_ids: Enum.sort(actionable_diff_light_ids)
    )

    log_light_decisions(
      trace,
      room_lights,
      diff_light_ids,
      effective_desired_by_light,
      physical_by_light
    )

    actions =
      actionable_diff_light_ids
      |> Enum.group_by(fn id ->
        desired = Map.get(effective_desired_by_light, id) || %{}
        {desired_key(desired), desired, light_bridge(room_lights, id)}
      end)
      |> Enum.flat_map(fn {{_key, desired, bridge_id}, ids} ->
        candidate_ids =
          room_lights
          |> Enum.filter(fn light ->
            light.bridge_id == bridge_id and
              desired_key(Map.get(effective_desired_by_light, light.id) || %{}) ==
                desired_key(desired)
          end)
          |> Enum.map(& &1.id)
          |> MapSet.new()

        log_trace(trace, "planner_partition",
          bridge_id: bridge_id,
          desired: desired,
          actionable_ids: Enum.sort(ids),
          candidate_ids: candidate_ids |> MapSet.to_list() |> Enum.sort()
        )

        groups = Enum.filter(group_memberships, &(&1.bridge_id == bridge_id))

        {group_actions, remaining} =
          plan_groups(groups, candidate_ids, MapSet.new(ids), desired, trace)

        log_trace(trace, "planner_partition_result",
          bridge_id: bridge_id,
          desired: desired,
          group_action_ids: Enum.map(group_actions, & &1.id),
          remaining_light_ids: remaining |> MapSet.to_list() |> Enum.sort()
        )

        group_actions ++ plan_lights(remaining, bridge_id, desired)
      end)

    log_trace(trace, "planner_output",
      room_id: room_id,
      actions_total: length(actions),
      group_actions: Enum.count(actions, &(&1.type == :group)),
      light_actions: Enum.count(actions, &(&1.type == :light))
    )

    actions
  end

  defp light_bridge(room_lights, id) do
    case Enum.find(room_lights, &(&1.id == id)) do
      nil -> nil
      %{bridge_id: bridge_id} -> bridge_id
    end
  end

  defp plan_groups(groups, candidate_set, remaining_diff, desired, trace) do
    case pick_group(groups, candidate_set, remaining_diff) do
      nil ->
        {[], remaining_diff}

      group ->
        log_trace(trace, "planner_group_pick",
          group_id: group.id,
          bridge_id: group.bridge_id,
          group_light_ids: group.lights |> MapSet.to_list() |> Enum.sort(),
          candidate_ids: candidate_set |> MapSet.to_list() |> Enum.sort(),
          remaining_diff_ids: remaining_diff |> MapSet.to_list() |> Enum.sort(),
          desired: desired
        )

        updated_remaining = MapSet.difference(remaining_diff, group.lights)

        {rest, final_remaining} =
          plan_groups(groups, candidate_set, updated_remaining, desired, trace)

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

  defp effective_desired_for_light(desired, light) when is_map(desired) do
    LightStateSemantics.effective_desired_for_light(desired, light)
  end

  defp effective_desired_for_light(_desired, _light), do: %{}

  defp desired_differs_from_physical?(desired, _physical) when map_size(desired) == 0, do: false

  # Keep explicit off intents actionable even when state currently appears off.
  defp desired_differs_from_physical?(desired, physical) do
    if explicit_off_intent?(desired) do
      true
    else
      desired_differs_from_physical_values?(desired, physical)
    end
  end

  defp desired_differs_from_physical_values?(desired, physical)
       when is_map(desired) and is_map(physical) do
    map_size(
      LightStateSemantics.diff_state(physical, desired,
        brightness_tolerance: @brightness_tolerance,
        temperature_mired_tolerance: @temperature_physical_mired_tolerance
      )
    ) > 0
  end

  defp desired_differs_from_physical_values?(_desired, _physical), do: true

  defp explicit_off_intent?(desired) when is_map(desired) do
    case Map.get(desired, :power) || Map.get(desired, "power") do
      :off -> true
      "off" -> true
      _ -> false
    end
  end

  defp log_light_decisions(
         nil,
         _room_lights,
         _diff_light_ids,
         _effective_desired_by_light,
         _physical_by_light
       ),
       do: :ok

  defp log_light_decisions(
         trace,
         room_lights,
         diff_light_ids,
         effective_desired_by_light,
         physical_by_light
       ) do
    diff_light_ids = MapSet.new(diff_light_ids)

    Enum.each(room_lights, fn light ->
      if MapSet.member?(diff_light_ids, light.id) do
        desired = Map.get(effective_desired_by_light, light.id) || %{}
        physical = Map.get(physical_by_light, light.id, %{})
        actionable = desired_differs_from_physical?(desired, physical)

        reason =
          cond do
            map_size(desired) == 0 -> :empty_desired
            actionable -> :differs_from_physical
            true -> :physical_already_matches
          end

        log_trace(trace, "planner_light_decision",
          light_id: light.id,
          bridge_id: light.bridge_id,
          desired: desired,
          physical: physical,
          actionable: actionable,
          reason: reason
        )
      end
    end)
  end

  defp log_trace(nil, _event, _kv), do: :ok

  defp log_trace(trace, event, kv) when is_map(trace) and is_list(kv) do
    trace_id = Map.get(trace, :trace_id) || Map.get(trace, "trace_id")
    source = Map.get(trace, :source) || Map.get(trace, "source")

    attrs =
      kv
      |> Enum.map_join(" ", fn {key, value} -> "#{key}=#{inspect(value)}" end)

    DebugLogging.info("[occ-trace #{trace_id}] #{event} source=#{source} #{attrs}")
  end
end
