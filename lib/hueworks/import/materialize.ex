defmodule Hueworks.Import.Materialize do
  @moduledoc false

  import Ecto.Query, only: [from: 2]

  alias Hueworks.Repo
  alias Hueworks.Import.{Normalize, Plan}
  alias Hueworks.Util
  alias Hueworks.Schemas.{Group, GroupLight, Light, Room}

  def materialize(bridge, normalized) do
    materialize(bridge, normalized, Plan.build_default(normalized))
  end

  def materialize(bridge, normalized, plan) do
    rooms = Normalize.fetch(normalized, :rooms) || []
    groups = Normalize.fetch(normalized, :groups) || []
    lights = Normalize.fetch(normalized, :lights) || []
    memberships = Normalize.fetch(normalized, :memberships) || %{}

    plan_rooms = Normalize.fetch(plan, :rooms) || %{}
    plan_lights = Normalize.fetch(plan, :lights) || %{}
    plan_groups = Normalize.fetch(plan, :groups) || %{}

    room_map = upsert_rooms(rooms, plan_rooms)
    lights = filter_entities(lights, plan_lights)
    groups = filter_entities(groups, plan_groups)
    memberships = filter_memberships(memberships, plan_lights, plan_groups)

    light_map = upsert_lights(bridge, lights, room_map)
    group_map = upsert_groups(bridge, groups, room_map)

    upsert_group_lights(memberships, light_map, group_map)
    infer_group_rooms(group_map)

    :ok
  end

  defp upsert_rooms(rooms, plan_rooms) do
    Enum.reduce(rooms, %{}, fn room, acc ->
      source_id = Normalize.normalize_source_id(Normalize.fetch(room, :source_id))
      name = Normalize.fetch(room, :name) || "Room"
      normalized_name = Normalize.normalize_room_name(name)
      plan = Normalize.fetch(plan_rooms, source_id) || %{}
      action = Normalize.fetch(plan, :action) || "create"

      room_record =
        if is_binary(source_id) do
          case action do
            "skip" ->
              nil

            "merge" ->
              target_room_id = Normalize.fetch(plan, :target_room_id)

              case normalize_room_target_id(target_room_id) do
                nil -> nil
                id -> Repo.get(Room, id)
              end

            _ ->
              existing =
                Repo.one(
                  from(r in Room,
                    where: fragment("lower(?)", r.name) == ^normalized_name
                  )
                )

              case existing do
                nil ->
                  %Room{}
                  |> Room.changeset(%{
                    name: name,
                    metadata: %{"normalized_name" => normalized_name}
                  })
                  |> Repo.insert!()

                room ->
                  room
              end
          end
        end

      if source_id && room_record do
        Map.put(acc, source_id, room_record.id)
      else
        acc
      end
    end)
  end

  defp upsert_lights(bridge, lights, room_map) do
    bridge_id = bridge.id

    Enum.reduce(lights, %{}, fn light, acc ->
      source_id = Normalize.normalize_source_id(Normalize.fetch(light, :source_id))

      if is_binary(source_id) do
        attrs = %{
          name: Normalize.fetch(light, :name) || "Light",
          source: normalize_source(Normalize.fetch(light, :source)),
          source_id: source_id,
          bridge_id: bridge_id,
          room_id: room_id_for(light, room_map),
          supports_color: !!Normalize.fetch(Normalize.fetch(light, :capabilities) || %{}, :color),
          supports_temp:
            !!Normalize.fetch(Normalize.fetch(light, :capabilities) || %{}, :color_temp),
          reported_min_kelvin:
            Normalize.fetch(Normalize.fetch(light, :capabilities) || %{}, :reported_kelvin_min),
          reported_max_kelvin:
            Normalize.fetch(Normalize.fetch(light, :capabilities) || %{}, :reported_kelvin_max),
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

        Map.put(acc, source_id, record.id)
      else
        acc
      end
    end)
  end

  defp upsert_groups(bridge, groups, room_map) do
    bridge_id = bridge.id

    Enum.reduce(groups, %{}, fn group, acc ->
      source_id = Normalize.normalize_source_id(Normalize.fetch(group, :source_id))

      if is_binary(source_id) do
        attrs = %{
          name: Normalize.fetch(group, :name) || "Group",
          source: normalize_source(Normalize.fetch(group, :source)),
          source_id: source_id,
          bridge_id: bridge_id,
          room_id: room_id_for(group, room_map),
          supports_color: !!Normalize.fetch(Normalize.fetch(group, :capabilities) || %{}, :color),
          supports_temp:
            !!Normalize.fetch(Normalize.fetch(group, :capabilities) || %{}, :color_temp),
          reported_min_kelvin:
            Normalize.fetch(Normalize.fetch(group, :capabilities) || %{}, :reported_kelvin_min),
          reported_max_kelvin:
            Normalize.fetch(Normalize.fetch(group, :capabilities) || %{}, :reported_kelvin_max),
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

        Map.put(acc, source_id, record.id)
      else
        acc
      end
    end)
  end

  defp upsert_group_lights(memberships, light_map, group_map) do
    group_lights = Normalize.fetch(memberships, :group_lights) || []

    Enum.each(group_lights, fn member ->
      group_id = Normalize.normalize_source_id(Normalize.fetch(member, :group_source_id))
      light_id = Normalize.normalize_source_id(Normalize.fetch(member, :light_source_id))

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

  defp infer_group_rooms(group_map) do
    group_ids = Map.values(group_map)

    if group_ids == [] do
      :ok
    else
      Repo.all(
        from(gl in GroupLight,
          join: l in Light,
          on: l.id == gl.light_id,
          where: gl.group_id in ^group_ids,
          select: {gl.group_id, l.room_id}
        )
      )
      |> Enum.group_by(fn {group_id, _room_id} -> group_id end, fn {_group_id, room_id} ->
        room_id
      end)
      |> Enum.each(fn {group_id, room_ids} ->
        rooms =
          room_ids
          |> Enum.filter(&is_integer/1)
          |> Enum.uniq()

        case rooms do
          [room_id] ->
            from(g in Group, where: g.id == ^group_id)
            |> Repo.update_all(set: [room_id: room_id])

          _ ->
            :ok
        end
      end)
    end
  end

  defp filter_entities(entities, plan_map) do
    Enum.filter(entities, fn entity ->
      source_id = Normalize.normalize_source_id(Normalize.fetch(entity, :source_id))

      case Normalize.fetch(plan_map, source_id) do
        false -> false
        true -> true
        nil -> true
        _ -> true
      end
    end)
  end

  defp normalize_room_target_id(id), do: Util.parse_optional_integer(id)

  defp filter_memberships(memberships, plan_lights, plan_groups) do
    group_lights = Normalize.fetch(memberships, :group_lights) || []

    filtered =
      Enum.filter(group_lights, fn membership ->
        group_id = Normalize.normalize_source_id(Normalize.fetch(membership, :group_source_id))
        light_id = Normalize.normalize_source_id(Normalize.fetch(membership, :light_source_id))

        group_ok = plan_selected?(plan_groups, group_id)
        light_ok = plan_selected?(plan_lights, light_id)

        group_ok and light_ok
      end)

    Map.put(memberships, :group_lights, filtered)
  end

  defp plan_selected?(_plan, nil), do: false

  defp plan_selected?(plan, source_id) do
    case Normalize.fetch(plan, source_id) do
      false -> false
      true -> true
      nil -> true
      _ -> true
    end
  end

  defp room_id_for(entry, room_map) do
    room_source_id = Normalize.normalize_source_id(Normalize.fetch(entry, :room_source_id))

    case room_source_id do
      nil -> nil
      _ -> Map.get(room_map, room_source_id)
    end
  end

  defp light_metadata(light, bridge_host) do
    base = Normalize.fetch(light, :metadata) || %{}
    identifiers = Normalize.fetch(light, :identifiers) || %{}

    base
    |> Map.put("identifiers", identifiers)
    |> Map.put_new("bridge_host", bridge_host)
  end

  defp group_metadata(group, bridge_host) do
    (Normalize.fetch(group, :metadata) || %{})
    |> Map.put_new("bridge_host", bridge_host)
  end

  defp normalize_source(source) when is_atom(source), do: source
  defp normalize_source(source) when is_binary(source), do: String.to_atom(source)
  defp normalize_source(_source), do: nil
end
