defmodule Hueworks.Import.Link do
  @moduledoc false

  import Ecto.Query, only: [from: 2]

  alias Hueworks.Repo
  alias Hueworks.Schemas.{Bridge, Group, GroupLight, Light}

  def apply do
    Repo.all(from(b in Bridge, where: b.type == :ha))
    |> Enum.each(&apply/1)

    :ok
  end

  def apply(%Bridge{type: :ha} = bridge) do
    link_ha_lights(bridge.id)
    link_ha_groups(bridge.id)
    :ok
  end

  def apply(%Bridge{}), do: :ok

  defp link_ha_lights(bridge_id) do
    non_ha_lights =
      Repo.all(
        from(l in Light,
          where: l.source in [:hue, :caseta] and is_nil(l.canonical_light_id)
        )
      )

    mac_index =
      Enum.reduce(non_ha_lights, %{}, fn light, acc ->
        case identifier(light, "mac") do
          nil -> acc
          mac -> Map.put(acc, mac, light.id)
        end
      end)

    serial_index =
      Enum.reduce(non_ha_lights, %{}, fn light, acc ->
        case identifier(light, "serial") do
          nil -> acc
          serial -> Map.put(acc, serial, light.id)
        end
      end)

    Repo.all(
      from(l in Light,
        where: l.bridge_id == ^bridge_id and l.source == :ha and is_nil(l.canonical_light_id)
      )
    )
    |> Enum.each(fn light ->
      canonical_id = canonical_light_for(light, mac_index, serial_index)

      if is_integer(canonical_id) do
        light
        |> Light.changeset(%{canonical_light_id: canonical_id})
        |> Repo.update()
      else
        :ok
      end
    end)
  end

  defp canonical_light_for(light, mac_index, serial_index) do
    mac = identifier(light, "mac")
    serial = identifier(light, "serial")

    cond do
      is_binary(mac) and Map.has_key?(mac_index, mac) -> Map.get(mac_index, mac)
      is_binary(serial) and Map.has_key?(serial_index, serial) -> Map.get(serial_index, serial)
      true -> nil
    end
  end

  defp link_ha_groups(bridge_id) do
    ha_groups =
      Repo.all(
        from(g in Group,
          where: g.bridge_id == ^bridge_id and g.source == :ha and is_nil(g.canonical_group_id)
        )
      )

    non_ha_members =
      Repo.all(
        from(gl in GroupLight,
          join: g in Group,
          on: g.id == gl.group_id,
          where: g.source in [:hue, :caseta] and is_nil(g.canonical_group_id),
          select: {gl.group_id, gl.light_id}
        )
      )
      |> group_member_sets()

    ha_members =
      Repo.all(
        from(gl in GroupLight,
          join: l in Light,
          on: l.id == gl.light_id,
          where: gl.group_id in ^Enum.map(ha_groups, & &1.id),
          select: {gl.group_id, l.canonical_light_id}
        )
      )
      |> group_member_sets()

    Enum.each(ha_groups, fn group ->
      member_set = Map.get(ha_members, group.id, MapSet.new())

      if MapSet.size(member_set) > 0 and not MapSet.member?(member_set, nil) do
        case find_matching_group(member_set, non_ha_members) do
          nil ->
            :ok

          canonical_group_id ->
            group
            |> Group.changeset(%{canonical_group_id: canonical_group_id})
            |> Repo.update()
        end
      end
    end)
  end

  defp find_matching_group(member_set, non_ha_members) do
    non_ha_members
    |> Enum.find_value(fn {group_id, other_set} ->
      if MapSet.equal?(member_set, other_set) do
        group_id
      else
        nil
      end
    end)
  end

  defp group_member_sets(pairs) do
    Enum.reduce(pairs, %{}, fn {group_id, light_id}, acc ->
      Map.update(acc, group_id, MapSet.new([light_id]), &MapSet.put(&1, light_id))
    end)
  end

  defp identifier(%Light{metadata: metadata}, key) when is_map(metadata) do
    identifiers = metadata["identifiers"] || %{}
    value = identifiers[key]
    if is_binary(value) and value != "", do: value, else: nil
  end

  defp identifier(_light, _key), do: nil
end
