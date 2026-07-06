defmodule Hueworks.Control.Z2MTopology do
  @moduledoc false

  import Ecto.Query, only: [from: 2]

  alias Hueworks.Repo
  alias Hueworks.Schemas.{Group, Light}

  def load_indexes(bridge_id) do
    lights =
      Repo.all(
        from(l in Light,
          where:
            l.bridge_id == ^bridge_id and l.source == :z2m and l.enabled == true and
              is_nil(l.canonical_light_id)
        )
      )

    groups =
      Repo.all(
        from(g in Group,
          where:
            g.bridge_id == ^bridge_id and g.source == :z2m and g.enabled == true and
              is_nil(g.canonical_group_id)
        )
      )

    lights_by_source_id =
      Enum.reduce(lights, %{}, fn light, acc -> Map.put(acc, light.source_id, light) end)

    groups_by_source_id =
      Enum.reduce(groups, %{}, fn group, acc -> Map.put(acc, group.source_id, group) end)

    group_member_lights =
      Enum.reduce(groups, %{}, fn group, acc ->
        members = get_in(group.metadata, ["members"]) || []

        lights =
          members
          |> Enum.map(&Map.get(lights_by_source_id, to_string(&1)))
          |> Enum.filter(&is_map/1)

        Map.put(acc, group.source_id, lights)
      end)

    %{
      lights_by_source_id: lights_by_source_id,
      groups_by_source_id: groups_by_source_id,
      group_member_lights: group_member_lights,
      group_source_ids_by_light_source_id: invert_group_members(group_member_lights)
    }
  end

  def entity_from_topic(topic_levels, base_levels)
      when is_list(topic_levels) and is_list(base_levels) do
    if Enum.take(topic_levels, length(base_levels)) == base_levels do
      rest = Enum.drop(topic_levels, length(base_levels))

      cond do
        rest == [] ->
          nil

        hd(rest) == "bridge" ->
          nil

        List.last(rest) in ["set", "get", "availability"] ->
          nil

        List.last(rest) == "state" and length(rest) > 1 ->
          rest
          |> Enum.drop(-1)
          |> Enum.join("/")

        true ->
          Enum.join(rest, "/")
      end
    end
  end

  def entity_from_topic(_topic_levels, _base_levels), do: nil

  defp invert_group_members(group_member_lights) do
    Enum.reduce(group_member_lights, %{}, fn {group_source_id, lights}, acc ->
      Enum.reduce(lights, acc, fn light, inner ->
        Map.update(inner, light.source_id, [group_source_id], &[group_source_id | &1])
      end)
    end)
  end
end
