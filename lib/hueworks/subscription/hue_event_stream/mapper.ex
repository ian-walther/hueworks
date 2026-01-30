defmodule Hueworks.Subscription.HueEventStream.Mapper do
  @moduledoc false

  import Ecto.Query, only: [from: 2]

  alias Hueworks.Control.State
  alias Hueworks.Util
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
      maybe_update_groups_from_light(state, db_id, attrs)
    else
      _ -> :ok
    end
  end

  def handle_resource(%{"type" => "grouped_light"} = resource, state) do
    with {:ok, v1_id} <- v1_group_id(resource),
         %{id: db_id} <- Map.get(state.groups_by_id, v1_id) do
      attrs = event_state_from_group(resource)
      State.put(:group, db_id, attrs)
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
    %{}
    |> Map.merge(extract_power(event))
    |> Map.merge(extract_brightness(event))
    |> Map.merge(extract_kelvin(event))
  end

  defp event_state_from_group(event), do: event_state_from_light(event)

  defp extract_power(event) do
    case get_in(event, ["on", "on"]) do
      true -> %{power: :on}
      false -> %{power: :off}
      _ -> %{}
    end
  end

  defp extract_brightness(event) do
    case get_in(event, ["dimming", "brightness"]) do
      value when is_number(value) ->
        %{brightness: Util.clamp(round(value), 1, 100)}

      _ ->
        %{}
    end
  end

  defp extract_kelvin(event) do
    mired =
      case event["color_temperature"] do
        %{"mirek" => value} -> to_number(value)
        %{:mirek => value} -> to_number(value)
        value -> to_number(value)
      end

    if is_number(mired) and mired > 0 do
      %{kelvin: round(1_000_000 / mired)}
    else
      %{}
    end
  end

  defp to_number(value) when is_integer(value), do: value
  defp to_number(value) when is_float(value), do: value

  defp to_number(value) when is_binary(value) do
    case Float.parse(value) do
      {number, ""} -> number
      _ -> nil
    end
  end

  defp to_number(_value), do: nil

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

  defp maybe_update_groups_from_light(state, light_id, attrs) do
    if Map.has_key?(attrs, :kelvin) do
      group_ids = Map.get(state.group_light_ids, light_id, [])

      Enum.each(group_ids, fn group_id ->
        case Map.get(state.group_lights, group_id, []) do
          [] ->
            :ok

          member_ids ->
            case group_kelvin_average(member_ids, 50) do
              {:ok, avg_kelvin} ->
                State.put(:group, group_id, %{kelvin: avg_kelvin})

              :error ->
                :ok
            end
        end
      end)
    end
  end

  defp group_kelvin_average(member_ids, tolerance) do
    kelvins =
      member_ids
      |> Enum.map(fn member_id ->
        case State.get(:light, member_id) do
          %{kelvin: member_kelvin} when is_number(member_kelvin) -> member_kelvin
          _ -> nil
        end
      end)
      |> Enum.reject(&is_nil/1)

    if length(kelvins) == length(member_ids) do
      min_k = Enum.min(kelvins)
      max_k = Enum.max(kelvins)

      if max_k - min_k <= tolerance do
        avg = round(Enum.sum(kelvins) / length(kelvins))
        {:ok, avg}
      else
        :error
      end
    else
      :error
    end
  end

end
