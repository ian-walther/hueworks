defmodule Hueworks.Control.Planner.Action do
  @moduledoc false

  defstruct [:type, :id, :bridge_id, :desired, :light_ids, :apply_opts]

  def light(id, bridge_id, desired, apply_opts \\ %{}) do
    %__MODULE__{
      type: :light,
      id: id,
      bridge_id: bridge_id,
      desired: desired,
      light_ids: [id],
      apply_opts: apply_opts
    }
  end

  def group(id, bridge_id, desired, light_ids, apply_opts \\ %{}) do
    %__MODULE__{
      type: :group,
      id: id,
      bridge_id: bridge_id,
      desired: desired,
      light_ids: normalize_light_ids(light_ids),
      apply_opts: apply_opts
    }
  end

  def to_map(%__MODULE__{} = action) do
    action
    |> Map.take([:type, :id, :bridge_id, :desired, :light_ids, :apply_opts])
    |> case do
      %{apply_opts: apply_opts} = map when apply_opts in [%{}, nil] ->
        Map.delete(map, :apply_opts)

      map ->
        map
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
