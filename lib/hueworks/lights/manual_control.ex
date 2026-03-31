defmodule Hueworks.Lights.ManualControl do
  @moduledoc false

  import Ecto.Query, only: [from: 2]

  alias Hueworks.Control.{DesiredState, Executor, Planner}
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
      {:ok, %{intent_diff: intent_diff}} ->
        _ = enqueue_diff(room_id, intent_diff)
        {:ok, intent_diff}

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
        {:ok, merged_updated_light_attrs(updated, light_ids)}

      {:ok, _diff, _updated} ->
        with {:ok, _diff} <- apply_updates(room_id, light_ids, %{power: :on}) do
          {:ok, %{power: :on}}
        end

      other ->
        other
    end
  end

  def apply_power_action(room_id, light_ids, action)
      when is_integer(room_id) and is_list(light_ids) and action in [:off, "off"] do
    with {:ok, _diff} <- apply_updates(room_id, light_ids, %{power: :off}) do
      {:ok, %{power: :off}}
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
end
