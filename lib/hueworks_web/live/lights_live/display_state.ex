defmodule HueworksWeb.LightsLive.DisplayState do
  @moduledoc false

  alias Hueworks.Kelvin
  alias Hueworks.Control.State

  def build_group_state(groups), do: build_entity_state(groups, :group)
  def build_light_state(lights), do: build_entity_state(lights, :light)

  def merge(existing, updates), do: Map.merge(existing, updates)
  def merge_light(existing, nil, updates), do: merge(existing, updates)

  def merge_light(existing, light, updates) do
    merged = merge(existing, updates)

    if preserve_extended_display_kelvin?(light, existing, updates) do
      Map.put(merged, :kelvin, existing[:kelvin])
    else
      merged
    end
  end

  def replace(_existing, updates), do: updates
  def replace_light(_existing, nil, updates), do: updates

  def replace_light(existing, light, updates) do
    if preserve_extended_display_kelvin?(light, existing, updates) do
      Map.put(updates, :kelvin, existing[:kelvin])
    else
      updates
    end
  end

  defp build_entity_state(entities, type) do
    Enum.reduce(entities, %{}, fn entity, acc ->
      {min_k, max_k} = Hueworks.Kelvin.derive_range(entity)
      kelvin = round((min_k + max_k) / 2)

      state =
        State.ensure(type, entity.id, %{
          brightness: 75,
          kelvin: kelvin,
          power: :off
        })

      Map.put(acc, entity.id, state)
    end)
  end

  defp preserve_extended_display_kelvin?(
         %{extended_kelvin_range: true} = light,
         existing,
         updates
       ) do
    current_kelvin = existing[:kelvin]
    incoming_kelvin = updates[:kelvin]
    ambiguous_floor = Kelvin.extended_boundary_kelvin(light)
    extended_boundary = Kelvin.extended_boundary_kelvin(light)

    is_number(current_kelvin) and current_kelvin < extended_boundary and
      is_number(incoming_kelvin) and
      incoming_kelvin == ambiguous_floor
  end

  defp preserve_extended_display_kelvin?(_light, _existing, _updates), do: false
end
