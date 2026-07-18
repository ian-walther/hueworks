defmodule Hueworks.Control.Planner do
  @moduledoc """
  Plans optimized control actions from desired state diffs.
  """

  alias Hueworks.DebugLogging
  alias Hueworks.Control.LightStateSemantics
  alias Hueworks.Control.Planner.Action
  alias Hueworks.Control.Planner.Context
  alias Hueworks.Control.AreaSnapshot
  alias Hueworks.Control.Transition

  @brightness_tolerance 2
  @temperature_physical_mired_tolerance 1
  @xy_tolerance 0.01

  def plan_area(area_id, diff, opts \\ []) when is_integer(area_id) and is_map(diff) do
    area_id
    |> AreaSnapshot.load()
    |> plan_snapshot(diff, opts)
  end

  def plan_snapshot(snapshot, diff, opts \\ []) when is_map(snapshot) and is_map(diff) do
    context = Context.from_snapshot(snapshot, opts)
    trace = context.trace
    diff_light_ids = Context.diff_light_ids(context, diff)

    actionable_diff_light_ids =
      Context.actionable_diff_light_ids(context, diff, &desired_differs_from_physical?/2)

    log_trace(trace, "planner_input",
      area_id: context.area_id,
      area_light_count: length(context.area_lights),
      diff_light_ids: Enum.sort(diff_light_ids),
      actionable_diff_light_ids: Enum.sort(actionable_diff_light_ids)
    )

    log_light_decisions(
      trace,
      context.area_lights,
      diff_light_ids,
      context.desired_by_light,
      context.physical_by_light
    )

    actions =
      actionable_diff_light_ids
      |> Enum.group_by(fn id ->
        desired = Context.desired_for_light(context, id)
        {desired_key(desired), desired, Context.bridge_for_light(context, id)}
      end)
      |> Enum.flat_map(fn {{_key, desired, bridge_id}, ids} ->
        candidate_ids =
          context.area_lights
          |> Enum.filter(fn light ->
            light.bridge_id == bridge_id and
              desired_key(Context.desired_for_light(context, light.id)) ==
                desired_key(desired)
          end)
          |> Enum.map(& &1.id)
          |> then(&Context.group_candidate_light_ids(context, &1))

        log_trace(trace, "planner_partition",
          bridge_id: bridge_id,
          desired: desired,
          actionable_ids: Enum.sort(ids),
          candidate_ids: candidate_ids |> MapSet.to_list() |> Enum.sort()
        )

        groups = Enum.filter(context.group_memberships, &(&1.bridge_id == bridge_id))

        {group_actions, remaining} =
          plan_groups(
            groups,
            candidate_ids,
            MapSet.new(ids),
            desired,
            context.transition_policy,
            context.physical_by_light,
            trace,
            context.operation,
            context.group_candidate_light_ids
          )

        log_trace(trace, "planner_partition_result",
          bridge_id: bridge_id,
          desired: desired,
          group_action_ids: Enum.map(group_actions, & &1.id),
          remaining_light_ids: remaining |> MapSet.to_list() |> Enum.sort()
        )

        group_actions ++
          plan_lights(
            remaining,
            bridge_id,
            desired,
            context.transition_policy,
            context.physical_by_light,
            context.operation,
            context.group_candidate_light_ids
          )
      end)
      |> Enum.map(&Action.to_map/1)
      |> Enum.map(&Action.attach_revisions(&1, context.desired_revisions_by_light))

    log_trace(trace, "planner_output",
      area_id: context.area_id,
      actions_total: length(actions),
      group_actions: Enum.count(actions, &(&1.type == :group)),
      light_actions: Enum.count(actions, &(&1.type == :light))
    )

    actions
  end

  defp plan_groups(
         groups,
         candidate_set,
         remaining_diff,
         desired,
         transition_policy,
         physical_by_light,
         trace,
         operation,
         group_candidate_light_ids
       ) do
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
          plan_groups(
            groups,
            candidate_set,
            updated_remaining,
            desired,
            transition_policy,
            physical_by_light,
            trace,
            operation,
            group_candidate_light_ids
          )

        apply_opts =
          action_apply_opts(
            transition_policy,
            desired,
            group.lights,
            physical_by_light
          )

        {[
           Action.group(
             group.id,
             group.bridge_id,
             desired,
             group.lights,
             apply_opts,
             operation,
             group_candidate_light_ids
           )
           | rest
         ], final_remaining}
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

  defp plan_lights(
         remaining_diff,
         bridge_id,
         desired,
         transition_policy,
         physical_by_light,
         operation,
         group_candidate_light_ids
       ) do
    remaining_diff
    |> MapSet.to_list()
    |> Enum.map(fn id ->
      apply_opts =
        action_apply_opts(
          transition_policy,
          desired,
          [id],
          physical_by_light
        )

      Action.light(
        id,
        bridge_id,
        desired,
        apply_opts,
        operation,
        group_candidate_light_ids
      )
    end)
  end

  defp desired_key(desired) when is_map(desired) do
    desired
    |> Map.to_list()
    |> Enum.sort()
  end

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
        temperature_mired_tolerance: @temperature_physical_mired_tolerance,
        xy_tolerance: @xy_tolerance
      )
    ) > 0
  end

  defp desired_differs_from_physical_values?(_desired, _physical), do: true

  defp action_apply_opts(
         transition_policy,
         desired,
         light_ids,
         physical_by_light
       ) do
    cond do
      transition_policy.duration_ms <= 0 ->
        %{}

      transition_policy.scaling != :brightness_delta ->
        Transition.apply_opts(transition_policy.duration_ms)

      not Transition.brightness_scalable?(desired) ->
        Transition.apply_opts(transition_policy.duration_ms)

      true ->
        normalize_light_ids(light_ids)
        |> Enum.map(fn id ->
          Transition.brightness_delta_percent(desired, Map.get(physical_by_light, id, %{}))
        end)
        |> Enum.filter(&is_integer/1)
        |> case do
          [] ->
            Transition.apply_opts(transition_policy.duration_ms)

          deltas ->
            scaled_ms = round(transition_policy.duration_ms * Enum.max(deltas) / 100)
            Transition.apply_opts(scaled_ms)
        end
    end
  end

  defp normalize_light_ids(%MapSet{} = light_ids), do: MapSet.to_list(light_ids)
  defp normalize_light_ids(light_ids) when is_list(light_ids), do: light_ids
  defp normalize_light_ids(light_id) when is_integer(light_id), do: [light_id]
  defp normalize_light_ids(_light_ids), do: []

  defp explicit_off_intent?(desired) when is_map(desired) do
    Map.get(desired, :power) == :off
  end

  defp log_light_decisions(
         nil,
         _area_lights,
         _diff_light_ids,
         _effective_desired_by_light,
         _physical_by_light
       ),
       do: :ok

  defp log_light_decisions(
         trace,
         area_lights,
         diff_light_ids,
         effective_desired_by_light,
         physical_by_light
       ) do
    diff_light_ids = MapSet.new(diff_light_ids)

    Enum.each(area_lights, fn light ->
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
    trace_id = Map.get(trace, :trace_id)
    source = Map.get(trace, :source)

    attrs =
      kv
      |> Enum.map_join(" ", fn {key, value} -> "#{key}=#{inspect(value)}" end)

    DebugLogging.info("[control-trace #{trace_id}] #{event} source=#{source} #{attrs}")
  end
end
