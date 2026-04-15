defmodule Hueworks.Control.Planner.Context do
  @moduledoc false

  alias Hueworks.AppSettings
  alias Hueworks.Control.LightStateSemantics
  alias Hueworks.Control.Transition

  defstruct [
    :room_id,
    :trace,
    :base_transition_ms,
    :scale_transition_by_brightness,
    room_lights: [],
    desired_by_light: %{},
    physical_by_light: %{},
    group_memberships: [],
    room_light_ids: MapSet.new()
  ]

  def from_snapshot(snapshot, opts) when is_map(snapshot) and is_list(opts) do
    room_lights = Map.get(snapshot, :room_lights, [])
    desired_by_light = Map.get(snapshot, :desired_by_light, %{})

    %__MODULE__{
      room_id: Map.get(snapshot, :room_id),
      trace: Keyword.get(opts, :trace),
      base_transition_ms: transition_ms(opts),
      scale_transition_by_brightness: scale_transition_by_brightness?(),
      room_lights: room_lights,
      desired_by_light: effective_desired_by_light(room_lights, desired_by_light),
      physical_by_light: Map.get(snapshot, :physical_by_light, %{}),
      group_memberships: Map.get(snapshot, :group_memberships, []),
      room_light_ids: MapSet.new(Enum.map(room_lights, & &1.id))
    }
  end

  def bridge_for_light(%__MODULE__{room_lights: room_lights}, id) do
    room_lights
    |> Enum.find(&(&1.id == id))
    |> case do
      nil -> nil
      %{bridge_id: bridge_id} -> bridge_id
    end
  end

  def diff_light_ids(%__MODULE__{room_light_ids: room_light_ids}, diff) when is_map(diff) do
    diff
    |> Map.keys()
    |> Enum.flat_map(fn
      {:light, id} when is_integer(id) -> [id]
      {"light", id} when is_integer(id) -> [id]
      _ -> []
    end)
    |> Enum.filter(&MapSet.member?(room_light_ids, &1))
  end

  def desired_for_light(%__MODULE__{desired_by_light: desired_by_light}, id) do
    Map.get(desired_by_light, id) || %{}
  end

  def physical_for_light(%__MODULE__{physical_by_light: physical_by_light}, id) do
    Map.get(physical_by_light, id, %{})
  end

  def actionable_diff_light_ids(%__MODULE__{} = context, diff, differs_fun)
      when is_function(differs_fun, 2) do
    context
    |> diff_light_ids(diff)
    |> Enum.filter(fn id ->
      differs_fun.(desired_for_light(context, id), physical_for_light(context, id))
    end)
  end

  def transition_ms(opts) when is_list(opts) do
    case Transition.transition_ms(opts) do
      value when is_integer(value) -> value
      _ -> default_transition_ms()
    end
  end

  defp effective_desired_by_light(room_lights, desired_by_light) do
    room_lights
    |> Map.new(fn light ->
      desired = Map.get(desired_by_light, light.id) || %{}
      {light.id, LightStateSemantics.effective_desired_for_light(desired, light)}
    end)
  end

  defp default_transition_ms do
    AppSettings.get_global().default_transition_ms || 0
  end

  defp scale_transition_by_brightness? do
    AppSettings.get_global().scale_transition_by_brightness == true
  end
end
