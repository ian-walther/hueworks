defmodule Hueworks.Subscription.HueEventStream.Mapper do
  @moduledoc false

  import Ecto.Query, only: [from: 2]

  alias Hueworks.Control.State
  alias Hueworks.Control.StateParser
  alias Hueworks.Schemas.Group
  alias Hueworks.Schemas.GroupLight
  alias Hueworks.Repo

  def load_group_maps(bridge_id) do
    group_lights = load_group_lights(bridge_id)
    group_light_ids = invert_group_lights(group_lights)
    {group_light_ids, group_lights}
  end

  def handle_resource(%{"type" => "light"} = resource, state) do
    with {:ok, v1_id} <- v1_id_from_event(resource, "/lights/"),
         %{id: db_id} <- Map.get(state.lights_by_id, v1_id) do
      attrs = event_state_from_light(resource)
      State.put(:light, db_id, attrs)
      refresh_groups_for_light(state, db_id, attrs)
    else
      _ -> :ok
    end
  end

  def handle_resource(%{"type" => "grouped_light"} = resource, state) do
    with {:ok, v1_id} <- v1_group_id(resource),
         %{id: db_id} <- Map.get(state.groups_by_id, v1_id) do
      attrs = event_state_from_group(resource)
      State.put(:group, db_id, attrs)
      maybe_update_lights_from_group(state, db_id, attrs)
    else
      _ -> :ok
    end
  end

  def handle_resource(_resource, _state), do: :ok

  def needs_refresh?(resources, state) when is_list(resources) do
    Enum.any?(resources, fn
      %{"type" => "light"} = resource ->
        case v1_id_from_event(resource, "/lights/") do
          {:ok, v1_id} -> Map.get(state.lights_by_id, v1_id) == nil
          _ -> false
        end

      %{"type" => "grouped_light"} = resource ->
        case v1_group_id(resource) do
          {:ok, v1_id} -> Map.get(state.groups_by_id, v1_id) == nil
          _ -> false
        end

      _ ->
        false
    end)
  end

  def needs_refresh?(_resources, _state), do: false

  defp v1_id_from_event(event, prefix) do
    v1_id_from_id_v1(event["id_v1"], prefix)
  end

  defp v1_id_from_id_v1(id_v1, prefix) when is_binary(id_v1) do
    case String.split(id_v1, prefix) do
      [_before, id] when id != "" -> {:ok, id}
      _ -> :error
    end
  end

  defp v1_id_from_id_v1(_id_v1, _prefix), do: :error

  defp v1_group_id(resource) do
    case v1_id_from_event(resource, "/groups/") do
      {:ok, _id} = ok ->
        ok

      :error ->
        owner_id_v1 = get_in(resource, ["owner", "id_v1"])
        v1_id_from_id_v1(owner_id_v1, "/groups/")
    end
  end

  defp event_state_from_light(event) do
    StateParser.hue_event_state(event)
  end

  defp event_state_from_group(event), do: event_state_from_light(event)

  defp load_group_lights(bridge_id) do
    Repo.all(
      from(gl in GroupLight,
        join: g in Group,
        on: g.id == gl.group_id,
        where: g.bridge_id == ^bridge_id and g.source == :hue,
        select: {gl.group_id, gl.light_id}
      )
    )
    |> Enum.reduce(%{}, fn {group_id, light_id}, acc ->
      Map.update(acc, group_id, [light_id], fn existing -> [light_id | existing] end)
    end)
  end

  defp invert_group_lights(group_lights) do
    Enum.reduce(group_lights, %{}, fn {group_id, light_ids}, acc ->
      Enum.reduce(light_ids, acc, fn light_id, inner ->
        Map.update(inner, light_id, [group_id], fn existing -> [group_id | existing] end)
      end)
    end)
  end

  defp maybe_update_lights_from_group(state, group_id, attrs) do
    if attrs == %{} do
      :ok
    else
      light_ids = Map.get(state.group_lights, group_id, [])

      Enum.each(light_ids, fn light_id ->
        State.put(:light, light_id, attrs)
      end)

      refresh_groups_for_lights(state, light_ids)
    end
  end

  defp refresh_groups_for_light(_state, _light_id, attrs) when attrs == %{}, do: :ok

  defp refresh_groups_for_light(state, light_id, _attrs) do
    refresh_groups_for_lights(state, [light_id])
  end

  defp refresh_groups_for_lights(state, light_ids) when is_list(light_ids) do
    light_ids
    |> Enum.flat_map(&Map.get(state.group_light_ids, &1, []))
    |> Enum.uniq()
    |> Enum.each(&refresh_group_from_members(state, &1))
  end

  defp refresh_groups_for_lights(_state, _light_ids), do: :ok

  defp refresh_group_from_members(state, group_id) do
    with member_ids when is_list(member_ids) <- Map.get(state.group_lights, group_id),
         derived when derived != %{} <- derive_group_state(member_ids) do
      State.put(:group, group_id, derived)
    else
      _ -> :ok
    end
  end

  defp derive_group_state(member_ids) when is_list(member_ids) do
    states =
      member_ids
      |> Enum.map(&State.get(:light, &1))
      |> Enum.reject(&is_nil/1)

    on_states =
      Enum.filter(states, fn
        %{power: power} when power in [:on, "on", true] -> true
        _ -> false
      end)

    base =
      cond do
        on_states != [] -> %{power: :on}
        states != [] and length(states) == length(member_ids) -> %{power: :off}
        true -> %{}
      end

    base
    |> maybe_put_group_brightness(on_states)
    |> maybe_put_group_kelvin(on_states)
    |> maybe_put_group_xy(on_states)
  end

  defp derive_group_state(_member_ids), do: %{}

  defp maybe_put_group_brightness(group_state, on_states) do
    on_states
    |> numeric_values(:brightness)
    |> put_average_if_complete(group_state, :brightness, length(on_states))
  end

  defp maybe_put_group_kelvin(group_state, on_states) do
    kelvin_values = numeric_values(on_states, :kelvin)

    if kelvin_values != [] and length(kelvin_values) == length(on_states) do
      min_k = Enum.min(kelvin_values)
      max_k = Enum.max(kelvin_values)

      if max_k - min_k <= 50 do
        Map.put(group_state, :kelvin, round(Enum.sum(kelvin_values) / length(kelvin_values)))
      else
        group_state
      end
    else
      group_state
    end
  end

  defp maybe_put_group_xy(group_state, on_states) do
    x_values = numeric_values(on_states, :x)
    y_values = numeric_values(on_states, :y)

    if xy_values_complete?(x_values, y_values, on_states) and values_within?(x_values, 0.01) and
         values_within?(y_values, 0.01) do
      group_state
      |> Map.put(:x, Float.round(Enum.sum(x_values) / length(x_values), 4))
      |> Map.put(:y, Float.round(Enum.sum(y_values) / length(y_values), 4))
    else
      group_state
    end
  end

  defp numeric_values(states, key) do
    states
    |> Enum.map(fn
      %{^key => value} when is_number(value) -> value
      _ -> nil
    end)
    |> Enum.reject(&is_nil/1)
  end

  defp put_average_if_complete([], group_state, _key, _expected_count), do: group_state

  defp put_average_if_complete(values, group_state, key, expected_count) do
    if length(values) == expected_count do
      Map.put(group_state, key, round(Enum.sum(values) / length(values)))
    else
      group_state
    end
  end

  defp xy_values_complete?(x_values, y_values, on_states) do
    expected_count = length(on_states)

    expected_count > 0 and length(x_values) == expected_count and
      length(y_values) == expected_count
  end

  defp values_within?(values, tolerance) when is_list(values) and values != [] do
    Enum.max(values) - Enum.min(values) <= tolerance
  end

  defp values_within?(_values, _tolerance), do: false
end
