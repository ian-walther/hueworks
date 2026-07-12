defmodule Hueworks.Control.Planner.Action do
  @moduledoc false

  defstruct [
    :type,
    :id,
    :bridge_id,
    :desired,
    :light_ids,
    :apply_opts,
    :operation,
    :group_candidate_light_ids
  ]

  def light(
        id,
        bridge_id,
        desired,
        apply_opts \\ %{},
        operation \\ nil,
        group_candidate_light_ids \\ nil
      ) do
    %__MODULE__{
      type: :light,
      id: id,
      bridge_id: bridge_id,
      desired: desired,
      light_ids: [id],
      apply_opts: apply_opts,
      operation: operation,
      group_candidate_light_ids: normalize_optional_light_ids(group_candidate_light_ids)
    }
  end

  def group(
        id,
        bridge_id,
        desired,
        light_ids,
        apply_opts \\ %{},
        operation \\ nil,
        group_candidate_light_ids \\ nil
      ) do
    %__MODULE__{
      type: :group,
      id: id,
      bridge_id: bridge_id,
      desired: desired,
      light_ids: normalize_light_ids(light_ids),
      apply_opts: apply_opts,
      operation: operation,
      group_candidate_light_ids: normalize_optional_light_ids(group_candidate_light_ids)
    }
  end

  def to_map(%__MODULE__{} = action) do
    action
    |> Map.take([
      :type,
      :id,
      :bridge_id,
      :desired,
      :light_ids,
      :apply_opts,
      :operation,
      :group_candidate_light_ids
    ])
    |> maybe_drop(:apply_opts, [%{}, nil])
    |> maybe_drop(:operation, [nil])
    |> maybe_drop(:group_candidate_light_ids, [nil])
  end

  def attach_revisions(action, revisions_by_light)
      when is_map(action) and is_map(revisions_by_light) do
    revisions =
      action
      |> Map.get(:light_ids, [])
      |> Enum.reduce(%{}, fn light_id, acc ->
        case Map.fetch(revisions_by_light, light_id) do
          {:ok, revision} -> Map.put(acc, {:light, light_id}, revision)
          :error -> acc
        end
      end)

    if map_size(revisions) == 0 do
      action
    else
      Map.put(action, :desired_revisions, revisions)
    end
  end

  defp normalize_light_ids(%MapSet{} = light_ids), do: MapSet.to_list(light_ids)
  defp normalize_light_ids(light_ids) when is_list(light_ids), do: light_ids

  defp normalize_optional_light_ids(nil), do: nil
  defp normalize_optional_light_ids(light_ids), do: normalize_light_ids(light_ids)

  defp maybe_drop(map, key, values) do
    if Map.get(map, key) in values, do: Map.delete(map, key), else: map
  end
end
