defmodule Hueworks.Control.Planner do
  @moduledoc """
  Plans optimized control actions from desired state diffs.
  """

  import Ecto.Query, only: [from: 2]
  require Logger

  alias Hueworks.DebugLogging
  alias Hueworks.Control.DesiredState
  alias Hueworks.Control.State, as: PhysicalState
  alias Hueworks.Kelvin
  alias Hueworks.Repo
  alias Hueworks.Schemas.{Group, GroupLight, Light}
  alias Hueworks.Util

  @brightness_tolerance 2
  @temperature_physical_mired_tolerance 1

  def plan_room(room_id, diff, opts \\ []) when is_integer(room_id) and is_map(diff) do
    trace = Keyword.get(opts, :trace)

    room_lights =
      Repo.all(
        from(l in Light,
          where: l.room_id == ^room_id,
          select: %{
            id: l.id,
            bridge_id: l.bridge_id,
            supports_temp: l.supports_temp,
            reported_min_kelvin: l.reported_min_kelvin,
            reported_max_kelvin: l.reported_max_kelvin,
            actual_min_kelvin: l.actual_min_kelvin,
            actual_max_kelvin: l.actual_max_kelvin,
            extended_kelvin_range: l.extended_kelvin_range
          }
        )
      )

    room_light_ids = MapSet.new(Enum.map(room_lights, & &1.id))

    desired_by_light =
      Map.new(room_lights, fn light ->
        {light.id, DesiredState.get(:light, light.id)}
      end)

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
        physical = PhysicalState.get(:light, id) || %{}
        desired_differs_from_physical?(desired, physical)
      end)

    group_memberships = load_group_memberships(room_id)

    log_trace(trace, "planner_input",
      room_id: room_id,
      room_light_count: length(room_lights),
      diff_light_ids: Enum.sort(diff_light_ids),
      actionable_diff_light_ids: Enum.sort(actionable_diff_light_ids)
    )

    log_light_decisions(trace, room_lights, diff_light_ids, effective_desired_by_light)

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
    case kelvin_value(desired) do
      nil ->
        desired

      kelvin ->
        if supports_temp?(light) do
          {min_kelvin, max_kelvin} = Kelvin.derive_range(light)
          clamped_kelvin = round(Util.clamp(kelvin, min_kelvin, max_kelvin))
          put_kelvin(desired, clamped_kelvin)
        else
          drop_kelvin(desired)
        end
    end
  end

  defp effective_desired_for_light(_desired, _light), do: %{}

  defp kelvin_value(desired) when is_map(desired) do
    desired
    |> Enum.find_value(fn
      {key, value} when key in [:kelvin, "kelvin", :temperature, "temperature"] ->
        Util.to_number(value)

      _ ->
        nil
    end)
    |> case do
      nil -> nil
      value -> round(value)
    end
  end

  defp supports_temp?(light) when is_map(light) do
    Map.get(light, :supports_temp) == true or Map.get(light, "supports_temp") == true
  end

  defp drop_kelvin(desired) do
    desired
    |> Map.delete(:kelvin)
    |> Map.delete("kelvin")
    |> Map.delete(:temperature)
    |> Map.delete("temperature")
  end

  defp put_kelvin(desired, clamped_kelvin) do
    keys =
      desired
      |> Map.keys()
      |> Enum.filter(&(&1 in [:kelvin, "kelvin", :temperature, "temperature"]))

    desired = drop_kelvin(desired)

    case keys do
      [] ->
        Map.put(desired, :kelvin, clamped_kelvin)

      _ ->
        Enum.reduce(keys, desired, fn key, acc ->
          Map.put(acc, key, clamped_kelvin)
        end)
    end
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
    Enum.any?(desired, fn {key, desired_value} ->
      physical_value = get_physical_value(physical, key)
      values_equal?(key, desired_value, physical_value) == false
    end)
  end

  defp desired_differs_from_physical_values?(_desired, _physical), do: true

  defp explicit_off_intent?(desired) when is_map(desired) do
    case Map.get(desired, :power) || Map.get(desired, "power") do
      :off -> true
      "off" -> true
      _ -> false
    end
  end

  defp log_light_decisions(nil, _room_lights, _diff_light_ids, _effective_desired_by_light), do: :ok

  defp log_light_decisions(trace, room_lights, diff_light_ids, effective_desired_by_light) do
    diff_light_ids = MapSet.new(diff_light_ids)

    Enum.each(room_lights, fn light ->
      if MapSet.member?(diff_light_ids, light.id) do
        desired = Map.get(effective_desired_by_light, light.id) || %{}
        physical = PhysicalState.get(:light, light.id) || %{}
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

  defp get_physical_value(physical, key) when is_map(physical) do
    key_aliases(key)
    |> Enum.find_value(fn alias_key ->
      Map.get(physical, alias_key)
    end)
  end

  defp key_aliases(:kelvin), do: [:kelvin, "kelvin", :temperature, "temperature"]
  defp key_aliases("kelvin"), do: [:kelvin, "kelvin", :temperature, "temperature"]
  defp key_aliases(:temperature), do: [:temperature, "temperature", :kelvin, "kelvin"]
  defp key_aliases("temperature"), do: [:temperature, "temperature", :kelvin, "kelvin"]
  defp key_aliases(:brightness), do: [:brightness, "brightness"]
  defp key_aliases("brightness"), do: [:brightness, "brightness"]
  defp key_aliases(:power), do: [:power, "power"]
  defp key_aliases("power"), do: [:power, "power"]
  defp key_aliases(key), do: [key]

  defp values_equal?(_key, desired, physical) when desired == physical, do: true

  defp values_equal?(key, desired, physical) when key in [:brightness, "brightness"] do
    case {Util.to_number(desired), Util.to_number(physical)} do
      {nil, _} -> desired == physical
      {_, nil} -> desired == physical
      {a, b} -> abs(round(a) - round(b)) <= @brightness_tolerance
    end
  end

  defp values_equal?(key, desired, physical)
       when key in [:kelvin, "kelvin", :temperature, "temperature"] do
    Kelvin.equivalent_temperature?(desired, physical,
      mired_tolerance: @temperature_physical_mired_tolerance
    )
  end

  defp values_equal?(_key, desired, physical), do: desired == physical

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
