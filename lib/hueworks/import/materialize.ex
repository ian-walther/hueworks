defmodule Hueworks.Import.Materialize do
  @moduledoc false

  import Ecto.Query, only: [from: 2]

  alias Hueworks.Repo
  alias Hueworks.Schemas.{Group, GroupLight, Light, Room}

  def apply(bridge, normalized) do
    rooms = fetch(normalized, :rooms) || []
    groups = fetch(normalized, :groups) || []
    lights = fetch(normalized, :lights) || []
    memberships = fetch(normalized, :memberships) || %{}

    room_map = upsert_rooms(rooms)
    light_map = upsert_lights(bridge, lights, room_map)
    group_map = upsert_groups(bridge, groups, room_map)

    upsert_group_lights(memberships, light_map, group_map)

    :ok
  end

  defp upsert_rooms(rooms) do
    Enum.reduce(rooms, %{}, fn room, acc ->
      source_id = normalize_source_id(fetch(room, :source_id))
      name = fetch(room, :name) || "Room"
      normalized_name = String.downcase(String.trim(name))

      existing =
        Repo.one(
          from(r in Room,
            where: fragment("lower(?)", r.name) == ^normalized_name
          )
        )

      room_record =
        case existing do
          nil ->
            %Room{}
            |> Room.changeset(%{name: name, metadata: %{"normalized_name" => normalized_name}})
            |> Repo.insert!()

          room ->
            room
        end

      if source_id do
        Map.put(acc, source_id, room_record.id)
      else
        acc
      end
    end)
  end

  defp upsert_lights(bridge, lights, room_map) do
    bridge_id = bridge.id

    Enum.reduce(lights, %{}, fn light, acc ->
      source_id = normalize_source_id(fetch(light, :source_id))

      attrs = %{
        name: fetch(light, :name) || "Light",
        source: normalize_source(fetch(light, :source)),
        source_id: source_id,
        bridge_id: bridge_id,
        room_id: room_id_for(light, room_map),
        supports_color: !!fetch(fetch(light, :capabilities) || %{}, :color),
        supports_temp: !!fetch(fetch(light, :capabilities) || %{}, :color_temp),
        reported_min_kelvin: fetch(fetch(light, :capabilities) || %{}, :reported_kelvin_min),
        reported_max_kelvin: fetch(fetch(light, :capabilities) || %{}, :reported_kelvin_max),
        metadata: light_metadata(light, bridge.host)
      }

      record =
        case Repo.get_by(Light, bridge_id: bridge_id, source_id: source_id) do
          nil ->
            %Light{}
            |> Light.changeset(attrs)
            |> Repo.insert!()

          existing ->
            existing
            |> Light.changeset(attrs)
            |> Repo.update!()
        end

      if source_id do
        Map.put(acc, source_id, record.id)
      else
        acc
      end
    end)
  end

  defp upsert_groups(bridge, groups, room_map) do
    bridge_id = bridge.id

    Enum.reduce(groups, %{}, fn group, acc ->
      source_id = normalize_source_id(fetch(group, :source_id))

      attrs = %{
        name: fetch(group, :name) || "Group",
        source: normalize_source(fetch(group, :source)),
        source_id: source_id,
        bridge_id: bridge_id,
        room_id: room_id_for(group, room_map),
        supports_color: !!fetch(fetch(group, :capabilities) || %{}, :color),
        supports_temp: !!fetch(fetch(group, :capabilities) || %{}, :color_temp),
        reported_min_kelvin: fetch(fetch(group, :capabilities) || %{}, :reported_kelvin_min),
        reported_max_kelvin: fetch(fetch(group, :capabilities) || %{}, :reported_kelvin_max),
        metadata: group_metadata(group, bridge.host)
      }

      record =
        case Repo.get_by(Group, bridge_id: bridge_id, source_id: source_id) do
          nil ->
            %Group{}
            |> Group.changeset(attrs)
            |> Repo.insert!()

          existing ->
            existing
            |> Group.changeset(attrs)
            |> Repo.update!()
        end

      if source_id do
        Map.put(acc, source_id, record.id)
      else
        acc
      end
    end)
  end

  defp upsert_group_lights(memberships, light_map, group_map) do
    group_lights = fetch(memberships, :group_lights) || []

    Enum.each(group_lights, fn member ->
      group_id = normalize_source_id(fetch(member, :group_source_id))
      light_id = normalize_source_id(fetch(member, :light_source_id))

      with true <- is_binary(group_id),
           true <- is_binary(light_id),
           db_group_id when is_integer(db_group_id) <- Map.get(group_map, group_id),
           db_light_id when is_integer(db_light_id) <- Map.get(light_map, light_id) do
        %GroupLight{}
        |> GroupLight.changeset(%{group_id: db_group_id, light_id: db_light_id})
        |> Repo.insert(on_conflict: :nothing, conflict_target: [:group_id, :light_id])
      else
        _ -> :ok
      end
    end)
  end

  defp room_id_for(entry, room_map) do
    room_source_id = normalize_source_id(fetch(entry, :room_source_id))

    case room_source_id do
      nil -> nil
      _ -> Map.get(room_map, room_source_id)
    end
  end

  defp light_metadata(light, bridge_host) do
    base = fetch(light, :metadata) || %{}
    identifiers = fetch(light, :identifiers) || %{}

    base
    |> Map.put("identifiers", identifiers)
    |> Map.put_new("bridge_host", bridge_host)
  end

  defp group_metadata(group, bridge_host) do
    (fetch(group, :metadata) || %{})
    |> Map.put_new("bridge_host", bridge_host)
  end


  defp normalize_source(source) when is_atom(source), do: source
  defp normalize_source(source) when is_binary(source), do: String.to_atom(source)
  defp normalize_source(_source), do: nil

  defp normalize_source_id(id) when is_binary(id), do: id
  defp normalize_source_id(id) when is_integer(id), do: Integer.to_string(id)
  defp normalize_source_id(id) when is_float(id), do: Float.to_string(id)
  defp normalize_source_id(_id), do: nil

  defp fetch(map, key) when is_map(map) do
    Map.get(map, key) || Map.get(map, Atom.to_string(key))
  end

  defp fetch(_map, _key), do: nil
end
