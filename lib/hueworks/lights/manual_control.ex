defmodule Hueworks.Lights.ManualControl do
  @moduledoc false

  alias Hueworks.ActiveScenes
  alias Hueworks.Control.Apply, as: ControlApply
  alias Hueworks.Control.DesiredState
  alias Hueworks.Control.ManualBaseline
  alias Hueworks.Scenes

  def apply_updates(room_id, light_ids, desired_update, opts \\ [])
      when is_list(light_ids) and is_map(desired_update) and is_list(opts) do
    if scene_active_manual_adjustment_blocked?(room_id, desired_update) do
      {:error, :scene_active_manual_adjustment_not_allowed}
    else
      txn = DesiredState.begin(:manual_ui)

      txn =
        Enum.reduce(light_ids, txn, fn light_id, acc ->
          DesiredState.apply(acc, :light, light_id, desired_update)
        end)

      case ControlApply.commit_and_enqueue(txn, room_id) do
        {:ok, %{plan_diff: plan_diff}} ->
          {:ok, plan_diff}

        other ->
          other
      end
    end
  end

  def apply_power_action(room_id, light_ids, :on)
      when is_integer(room_id) and is_list(light_ids) do
    trace = %{
      trace_id: "manual-on-#{room_id}-#{System.unique_integer([:positive])}",
      source: "lights_live.manual_power_on",
      started_at_ms: System.monotonic_time(:millisecond)
    }

    case ActiveScenes.get_for_room(room_id) do
      nil ->
        baseline = ManualBaseline.power_on_state()

        with {:ok, _diff} <- apply_updates(room_id, light_ids, baseline) do
          {:ok, baseline}
        end

      _active_scene ->
        case Scenes.recompute_active_scene_lights(room_id, light_ids,
               power_override: :on,
               trace: trace
             ) do
          {:ok, _diff, updated} when map_size(updated) > 0 ->
            {:ok, merged_updated_light_attrs(updated, light_ids)}

          {:ok, _diff, _updated} ->
            {:ok, %{power: :on}}

          other ->
            other
        end
    end
  end

  def apply_power_action(room_id, light_ids, action)
      when is_integer(room_id) and is_list(light_ids) and action in [:off, "off"] do
    trace = %{
      trace_id: "manual-off-#{room_id}-#{System.unique_integer([:positive])}",
      source: "lights_live.manual_power_off",
      started_at_ms: System.monotonic_time(:millisecond)
    }

    case ActiveScenes.get_for_room(room_id) do
      nil ->
        with {:ok, _diff} <- apply_updates(room_id, light_ids, %{power: :off}) do
          {:ok, %{power: :off}}
        end

      _active_scene ->
        case Scenes.recompute_active_scene_lights(room_id, light_ids,
               power_override: :off,
               trace: trace
             ) do
          {:ok, _diff, updated} when map_size(updated) > 0 ->
            {:ok, merged_updated_light_attrs(updated, light_ids)}

          {:ok, _diff, _updated} ->
            {:ok, %{power: :off}}

          other ->
            other
        end
    end
  end

  defp merged_updated_light_attrs(updated, light_ids) do
    light_ids
    |> Enum.reduce(%{}, fn light_id, acc ->
      Map.merge(acc, Map.get(updated, {:light, light_id}, %{}))
    end)
  end

  defp scene_active_manual_adjustment_blocked?(room_id, desired_update)
       when is_integer(room_id) and is_map(desired_update) do
    ActiveScenes.get_for_room(room_id) != nil and manual_adjustment_keys?(desired_update)
  end

  defp scene_active_manual_adjustment_blocked?(_room_id, _desired_update), do: false

  defp manual_adjustment_keys?(attrs) when is_map(attrs) do
    Enum.any?(Map.keys(attrs), fn
      :brightness -> true
      "brightness" -> true
      :kelvin -> true
      "kelvin" -> true
      :temperature -> true
      "temperature" -> true
      :x -> true
      "x" -> true
      :y -> true
      "y" -> true
      _ -> false
    end)
  end
end
