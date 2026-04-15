defmodule Hueworks.Control.Planner.Action do
  @moduledoc false

  defstruct [:type, :id, :bridge_id, :desired, :apply_opts]

  def light(id, bridge_id, desired, apply_opts \\ %{}) do
    %__MODULE__{
      type: :light,
      id: id,
      bridge_id: bridge_id,
      desired: desired,
      apply_opts: apply_opts
    }
  end

  def group(id, bridge_id, desired, apply_opts \\ %{}) do
    %__MODULE__{
      type: :group,
      id: id,
      bridge_id: bridge_id,
      desired: desired,
      apply_opts: apply_opts
    }
  end

  def to_map(%__MODULE__{} = action) do
    action
    |> Map.take([:type, :id, :bridge_id, :desired, :apply_opts])
    |> case do
      %{apply_opts: apply_opts} = map when apply_opts in [%{}, nil] ->
        Map.delete(map, :apply_opts)

      map ->
        map
    end
  end
end
