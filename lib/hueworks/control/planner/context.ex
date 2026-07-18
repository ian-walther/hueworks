defmodule Hueworks.Control.Planner.Context do
  @moduledoc false

  alias Hueworks.Control.LightStateSemantics
  alias Hueworks.Control.Operation
  alias Hueworks.Control.Transition
  alias Hueworks.Control.TransitionPolicy

  defstruct [
    :area_id,
    :trace,
    :operation,
    :transition_policy,
    area_lights: [],
    desired_by_light: %{},
    desired_revisions_by_light: %{},
    physical_by_light: %{},
    group_memberships: [],
    area_light_ids: MapSet.new(),
    group_candidate_light_ids: MapSet.new(),
    protected_light_ids: MapSet.new()
  ]

  def from_snapshot(snapshot, opts) when is_map(snapshot) and is_list(opts) do
    area_lights = Map.get(snapshot, :area_lights, [])
    desired_by_light = Map.get(snapshot, :desired_by_light, %{})
    area_light_ids = MapSet.new(Enum.map(area_lights, & &1.id))
    operation = Keyword.get(opts, :operation)

    %__MODULE__{
      area_id: Map.get(snapshot, :area_id),
      trace: operation_trace(operation, opts),
      operation: operation,
      transition_policy: transition_policy(operation, opts),
      area_lights: area_lights,
      desired_by_light: effective_desired_by_light(area_lights, desired_by_light),
      desired_revisions_by_light: Map.get(snapshot, :desired_revisions_by_light, %{}),
      physical_by_light: Map.get(snapshot, :physical_by_light, %{}),
      group_memberships: Map.get(snapshot, :group_memberships, []),
      area_light_ids: area_light_ids,
      group_candidate_light_ids: initial_group_candidate_light_ids(opts, area_light_ids),
      protected_light_ids: light_id_set(Keyword.get(opts, :protected_light_ids, []))
    }
  end

  def bridge_for_light(%__MODULE__{area_lights: area_lights}, id) do
    area_lights
    |> Enum.find(&(&1.id == id))
    |> case do
      nil -> nil
      %{bridge_id: bridge_id} -> bridge_id
    end
  end

  def diff_light_ids(%__MODULE__{area_light_ids: area_light_ids}, diff) when is_map(diff) do
    diff
    |> Map.keys()
    |> Enum.flat_map(fn
      {:light, id} when is_integer(id) -> [id]
      _ -> []
    end)
    |> Enum.filter(&MapSet.member?(area_light_ids, &1))
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

  def group_candidate_light_ids(%__MODULE__{} = context, ids) do
    ids
    |> light_id_set()
    |> MapSet.intersection(context.group_candidate_light_ids)
    |> MapSet.difference(context.protected_light_ids)
  end

  defp effective_desired_by_light(area_lights, desired_by_light) do
    area_lights
    |> Map.new(fn light ->
      desired = Map.get(desired_by_light, light.id) || %{}
      {light.id, LightStateSemantics.effective_desired_for_light(desired, light)}
    end)
  end

  defp operation_trace(%Operation{trace: trace}, _opts) when is_map(trace), do: trace
  defp operation_trace(_operation, opts), do: Keyword.get(opts, :trace)

  defp transition_policy(%Operation{transition_policy: policy}, _opts), do: policy

  defp transition_policy(_operation, opts) do
    case Transition.transition_ms(opts) do
      value when is_integer(value) -> %{TransitionPolicy.manual() | duration_ms: value}
      _ -> TransitionPolicy.manual()
    end
  end

  defp initial_group_candidate_light_ids(opts, area_light_ids) do
    case Keyword.get(opts, :group_candidate_light_ids) do
      nil -> area_light_ids
      :all -> area_light_ids
      ids -> light_id_set(ids) |> MapSet.intersection(area_light_ids)
    end
  end

  defp light_id_set(%MapSet{} = ids), do: ids
  defp light_id_set(ids) when is_list(ids), do: MapSet.new(Enum.filter(ids, &is_integer/1))
  defp light_id_set(_ids), do: MapSet.new()
end
