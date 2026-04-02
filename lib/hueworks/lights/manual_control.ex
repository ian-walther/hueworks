defmodule Hueworks.Lights.ManualControl do
  @moduledoc false

  import Ecto.Query, only: [from: 2]

  alias Hueworks.Control.{DesiredState, Executor, Planner}
  alias Hueworks.Control.State, as: PhysicalState
  alias Hueworks.Repo
  alias Hueworks.Scenes
  alias Hueworks.Schemas.Light

  def apply_updates(room_id, light_ids, desired_update)
      when is_list(light_ids) and is_map(desired_update) do
    txn = DesiredState.begin(:manual_ui)

    txn =
      Enum.reduce(light_ids, txn, fn light_id, acc ->
        DesiredState.apply(acc, :light, light_id, desired_update)
      end)

    case DesiredState.commit(txn) do
      {:ok, %{intent_diff: intent_diff, reconcile_diff: reconcile_diff}} ->
        plan_diff = merge_plan_diff(intent_diff, reconcile_diff)
        _ = enqueue_diff(room_id, plan_diff)
        {:ok, plan_diff}

      other ->
        other
    end
  end

  def apply_power_action(room_id, light_ids, :on)
      when is_integer(room_id) and is_list(light_ids) do
    trace = %{
      trace_id: "manual-on-#{room_id}-#{System.unique_integer([:positive])}",
      source: "lights_live.manual_power_on",
      started_at_ms: System.monotonic_time(:millisecond)
    }

    case Scenes.reapply_active_scene_lights(room_id, light_ids,
           power_override: :on,
           trace: trace
         ) do
      {:ok, _diff, updated} when map_size(updated) > 0 ->
        result = {:ok, merged_updated_light_attrs(updated, light_ids)}
        schedule_power_reconcile(room_id, light_ids)
        result

      {:ok, _diff, _updated} ->
        with {:ok, _diff} <- apply_updates(room_id, light_ids, %{power: :on}) do
          result = {:ok, %{power: :on}}
          schedule_power_reconcile(room_id, light_ids)
          result
        end

      other ->
        other
    end
  end

  def apply_power_action(room_id, light_ids, action)
      when is_integer(room_id) and is_list(light_ids) and action in [:off, "off"] do
    with {:ok, _diff} <- apply_updates(room_id, light_ids, %{power: :off}) do
      result = {:ok, %{power: :off}}
      schedule_power_reconcile(room_id, light_ids)
      result
    end
  end

  defp enqueue_diff(_room_id, diff) when map_size(diff) == 0, do: :ok

  defp enqueue_diff(room_id, diff) when is_integer(room_id) and is_map(diff) do
    plan = Planner.plan_room(room_id, diff)
    _ = Executor.enqueue(plan)
    :ok
  end

  defp enqueue_diff(_room_id, diff) when is_map(diff) do
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

    plan =
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

    _ = Executor.enqueue(plan)
    :ok
  end

  defp merged_updated_light_attrs(updated, light_ids) do
    light_ids
    |> Enum.reduce(%{}, fn light_id, acc ->
      Map.merge(acc, Map.get(updated, {:light, light_id}, %{}))
    end)
  end

  defp schedule_power_reconcile(room_id, light_ids)
       when is_integer(room_id) and is_list(light_ids) do
    delay_ms = Application.get_env(:hueworks, :manual_control_reconcile_delay_ms, 500)
    unique_light_ids = Enum.uniq(light_ids)

    if unique_light_ids != [] do
      Task.start(fn ->
        if delay_ms > 0 do
          Process.sleep(delay_ms)
        end

        enqueue_power_reconcile(room_id, unique_light_ids)
      end)
    end

    :ok
  end

  defp enqueue_power_reconcile(room_id, light_ids) do
    diff =
      Enum.reduce(light_ids, %{}, fn light_id, acc ->
        desired = DesiredState.get(:light, light_id) || %{}
        physical = PhysicalState.get(:light, light_id) || %{}

        case power_reconcile_delta(desired, physical) do
          nil -> acc
          delta -> Map.put(acc, {:light, light_id}, delta)
        end
      end)

    enqueue_diff(room_id, diff)
  end

  defp power_reconcile_delta(desired, physical) when is_map(desired) and is_map(physical) do
    desired_power = normalize_power(Map.get(desired, :power) || Map.get(desired, "power"))
    physical_power = normalize_power(Map.get(physical, :power) || Map.get(physical, "power"))

    cond do
      desired_power in [:on, :off] and desired_power != physical_power ->
        %{power: desired_power}

      true ->
        nil
    end
  end

  defp power_reconcile_delta(_desired, _physical), do: nil

  defp normalize_power(:on), do: :on
  defp normalize_power("on"), do: :on
  defp normalize_power(true), do: :on
  defp normalize_power(:off), do: :off
  defp normalize_power("off"), do: :off
  defp normalize_power(false), do: :off
  defp normalize_power(_value), do: nil

  defp merge_plan_diff(left, right) when left == %{}, do: right
  defp merge_plan_diff(left, right) when right == %{}, do: left

  defp merge_plan_diff(left, right) when is_map(left) and is_map(right) do
    Map.merge(left, right, fn _key, left_value, right_value ->
      Map.merge(left_value, right_value)
    end)
  end
end
