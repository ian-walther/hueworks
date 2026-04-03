defmodule Hueworks.Lights.ManualControl do
  @moduledoc false

  alias Hueworks.Control.Apply, as: ControlApply
  alias Hueworks.Control.DesiredState
  alias Hueworks.Scenes

  def apply_updates(room_id, light_ids, desired_update)
      when is_list(light_ids) and is_map(desired_update) do
    txn = DesiredState.begin(:manual_ui)

    txn =
      Enum.reduce(light_ids, txn, fn light_id, acc ->
        DesiredState.apply(acc, :light, light_id, desired_update)
      end)

    case ControlApply.commit_transaction(txn) do
      {:ok, %{plan_diff: plan_diff}} ->
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
        schedule_reconcile_passes(room_id, light_ids)
        result

      {:ok, _diff, _updated} ->
        with {:ok, _diff} <- apply_updates(room_id, light_ids, %{power: :on}) do
          result = {:ok, %{power: :on}}
          schedule_reconcile_passes(room_id, light_ids)
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
      schedule_reconcile_passes(room_id, light_ids)
      result
    end
  end

  defp enqueue_diff(_room_id, diff) when map_size(diff) == 0, do: :ok

  defp enqueue_diff(room_id, diff) when is_integer(room_id) and is_map(diff) do
    plan = ControlApply.build_plan(room_id, diff)
    _ = ControlApply.enqueue_plan(plan)
    :ok
  end

  defp enqueue_diff(_room_id, diff) when is_map(diff) do
    plan = ControlApply.build_plan(nil, diff)
    _ = ControlApply.enqueue_plan(plan)
    :ok
  end

  defp merged_updated_light_attrs(updated, light_ids) do
    light_ids
    |> Enum.reduce(%{}, fn light_id, acc ->
      Map.merge(acc, Map.get(updated, {:light, light_id}, %{}))
    end)
  end

  defp schedule_reconcile_passes(room_id, light_ids)
       when is_integer(room_id) and is_list(light_ids) do
    delays_ms =
      Application.get_env(
        :hueworks,
        :manual_control_reconcile_delays_ms,
        if(Mix.env() == :test, do: [], else: [500])
      )

    unique_light_ids = Enum.uniq(light_ids)

    Enum.each(List.wrap(delays_ms), fn delay_ms ->
      if unique_light_ids != [] do
        Task.start(fn ->
          if delay_ms > 0 do
            Process.sleep(delay_ms)
          end

          enqueue_current_desired(room_id, unique_light_ids)
        end)
      end
    end)

    :ok
  end

  defp enqueue_current_desired(room_id, light_ids) do
    diff =
      Enum.reduce(light_ids, %{}, fn light_id, acc ->
        desired = DesiredState.get(:light, light_id) || %{}

        if desired == %{} do
          acc
        else
          Map.put(acc, {:light, light_id}, desired)
        end
      end)

    enqueue_diff(room_id, diff)
  end

end
