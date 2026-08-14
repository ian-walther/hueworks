defmodule Hueworks.Control.Planner.Action do
  @moduledoc false

  def light(
        id,
        bridge_id,
        desired,
        apply_opts,
        operation,
        group_candidate_light_ids
      ) do
    action = %{
      type: :light,
      id: id,
      bridge_id: bridge_id,
      desired: desired,
      light_ids: [id]
    }

    action =
      if apply_opts in [%{}, nil], do: action, else: Map.put(action, :apply_opts, apply_opts)

    action = if is_nil(operation), do: action, else: Map.put(action, :operation, operation)

    if is_nil(group_candidate_light_ids) do
      action
    else
      Map.put(action, :group_candidate_light_ids, normalize_light_ids(group_candidate_light_ids))
    end
  end

  def group(
        id,
        bridge_id,
        desired,
        light_ids,
        apply_opts,
        operation,
        group_candidate_light_ids
      ) do
    action = %{
      type: :group,
      id: id,
      bridge_id: bridge_id,
      desired: desired,
      light_ids: normalize_light_ids(light_ids)
    }

    action =
      if apply_opts in [%{}, nil], do: action, else: Map.put(action, :apply_opts, apply_opts)

    action = if is_nil(operation), do: action, else: Map.put(action, :operation, operation)

    if is_nil(group_candidate_light_ids) do
      action
    else
      Map.put(action, :group_candidate_light_ids, normalize_light_ids(group_candidate_light_ids))
    end
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
end
