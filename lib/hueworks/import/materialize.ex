defmodule Hueworks.Import.Materialize do
  @moduledoc false

  import Ecto.Query, only: [from: 2]

  alias Hueworks.Import.{
    Duplicates,
    EntityAttrs,
    Normalize,
    Plan,
    ReimportApply,
    Rooms
  }

  alias Hueworks.Repo
  alias Hueworks.Schemas.{Group, GroupLight, Light}

  def materialize(bridge, normalized) do
    if imported_bridge?(bridge) do
      {:error, :reimport_requires_review}
    else
      materialize(bridge, normalized, Plan.build_default(normalized))
    end
  end

  def materialize(bridge, normalized, plan) do
    if imported_bridge?(bridge) do
      ReimportApply.apply(bridge, normalized, plan)
    else
      materialize_initial(bridge, normalized, plan)
    end
  end

  defp imported_bridge?(bridge) do
    bridge.import_complete or bridge_has_entities?(bridge.id)
  end

  defp bridge_has_entities?(bridge_id) do
    Repo.exists?(from(l in Light, where: l.bridge_id == ^bridge_id)) or
      Repo.exists?(from(g in Group, where: g.bridge_id == ^bridge_id))
  end

  defp materialize_initial(bridge, normalized, plan) do
    rooms = Normalize.fetch(normalized, :rooms) || []
    groups = (Normalize.fetch(normalized, :groups) || []) |> Duplicates.reject_hueworks_exported()
    lights = (Normalize.fetch(normalized, :lights) || []) |> Duplicates.reject_hueworks_exported()
    memberships = Normalize.fetch(normalized, :memberships) || %{}

    plan_rooms = Normalize.fetch(plan, :rooms) || %{}
    plan_lights = Normalize.fetch(plan, :lights) || %{}
    plan_groups = Normalize.fetch(plan, :groups) || %{}

    room_map = upsert_rooms(rooms, plan_rooms)
    lights = filter_entities(lights, plan_lights)
    groups = filter_entities(groups, plan_groups)
    memberships = filter_memberships(memberships, plan_lights, plan_groups)
    duplicate_light_targets = Duplicates.light_targets(lights)

    light_result = upsert_lights(bridge, lights, room_map, plan_lights, duplicate_light_targets)
    group_map = upsert_groups(bridge, groups, room_map, plan_groups, light_result)

    upsert_group_lights(memberships, light_result.source_id_to_db_id, group_map)
    infer_group_rooms(group_map)

    :ok
  end

  defp upsert_rooms(rooms, plan_rooms) do
    Enum.reduce(rooms, %{}, fn room, acc ->
      source_id = Normalize.normalize_source_id(Normalize.fetch(room, :source_id))

      if is_binary(source_id) do
        case Rooms.upsert(room, Normalize.fetch(plan_rooms, source_id) || %{}) do
          nil -> acc
          room_id -> Map.put(acc, source_id, room_id)
        end
      else
        acc
      end
    end)
  end

  defp upsert_lights(bridge, lights, room_map, plan_lights, duplicate_targets) do
    bridge_id = bridge.id

    initial = %{source_id_to_db_id: %{}, source_id_to_canonical_db_id: %{}}

    Enum.reduce(lights, initial, fn light, acc ->
      source_id = Normalize.normalize_source_id(Normalize.fetch(light, :source_id))

      if is_binary(source_id) do
        attrs =
          bridge
          |> EntityAttrs.light_attrs(light)
          |> Map.put(:room_id, Rooms.target_id_for(light, room_map, plan_lights))

        canonical_light_id = Map.get(duplicate_targets, source_id)

        attrs =
          if is_integer(canonical_light_id) do
            EntityAttrs.hidden_duplicate_overlay(attrs, canonical_light_id, :light)
          else
            attrs
          end

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

        canonical_id = canonical_light_id || record.canonical_light_id || record.id

        %{
          acc
          | source_id_to_db_id: Map.put(acc.source_id_to_db_id, source_id, record.id),
            source_id_to_canonical_db_id:
              Map.put(acc.source_id_to_canonical_db_id, source_id, canonical_id)
        }
      else
        acc
      end
    end)
  end

  defp upsert_groups(bridge, groups, room_map, plan_groups, light_result) do
    bridge_id = bridge.id

    Enum.reduce(groups, %{}, fn group, acc ->
      source_id = Normalize.normalize_source_id(Normalize.fetch(group, :source_id))

      if is_binary(source_id) do
        attrs =
          bridge
          |> EntityAttrs.group_attrs(group)
          |> Map.put(:room_id, Rooms.target_id_for(group, room_map, plan_groups))

        attrs =
          case Duplicates.group_target(group, light_result.source_id_to_canonical_db_id) do
            canonical_group_id when is_integer(canonical_group_id) ->
              EntityAttrs.hidden_duplicate_overlay(attrs, canonical_group_id, :group)

            _ ->
              attrs
          end

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
        %{} = entry -> Map.get(entry, "selected", true)
        true -> true
        nil -> true
        _ -> true
      end
    end)
  end

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
      %{} = entry -> Map.get(entry, "selected", true)
      true -> true
      nil -> true
      _ -> true
    end
  end
end
