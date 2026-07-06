defmodule Hueworks.Subscription.HueEventStream.Mapper do
  @moduledoc false

  import Ecto.Query, only: [from: 2]

  alias Hueworks.Control.{DesiredState, GroupState, State}
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
        State.put(
          :light,
          light_id,
          GroupState.member_attrs_from_group(
            attrs,
            DesiredState.get(:light, light_id),
            State.get(:light, light_id)
          )
        )
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
         derived when derived != %{} <- GroupState.derive_from_light_ids(member_ids) do
      State.put(:group, group_id, derived)
    else
      _ -> :ok
    end
  end
end
