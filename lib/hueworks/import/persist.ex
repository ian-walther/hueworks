defmodule Hueworks.Import.Persist do
  @moduledoc """
  Shared persistence helpers for importing bridges and lights.
  """

  import Ecto.Query, only: [from: 2]

  alias Hueworks.Bridges.Bridge
  alias Hueworks.Groups.Group
  alias Hueworks.Groups.GroupLight
  alias Hueworks.Lights.Light
  alias Hueworks.Repo

  def get_bridge!(type, host) do
    Repo.get_by!(Bridge, type: type, host: host)
  end

  def upsert_light(attrs) do
    changeset = Light.changeset(%Light{}, attrs)

    Repo.insert(
      changeset,
      on_conflict:
        {:replace,
         [:name, :metadata, :enabled, :canonical_light_id, :min_kelvin, :max_kelvin, :updated_at]},
      conflict_target: [:bridge_id, :source_id]
    )
  end

  def upsert_group(attrs) do
    changeset = Group.changeset(%Group{}, attrs)

    Repo.insert(
      changeset,
      on_conflict:
        {:replace,
         [:name, :metadata, :enabled, :parent_group_id, :canonical_group_id, :updated_at]},
      conflict_target: [:bridge_id, :source_id]
    )
  end

  def upsert_group_light(group_id, light_id) do
    changeset = GroupLight.changeset(%GroupLight{}, %{group_id: group_id, light_id: light_id})

    Repo.insert(
      changeset,
      on_conflict: :nothing,
      conflict_target: [:group_id, :light_id]
    )
  end

  def light_indexes do
    lights = Repo.all(Light)

    %{
      hue_by_mac: index_by_metadata(lights, :hue, "mac"),
      caseta_by_serial: index_by_metadata(lights, :caseta, "serial"),
      caseta_by_zone_id: index_by_source_id(lights, :caseta)
    }
  end

  def lights_by_source_id(bridge_id, source) do
    Repo.all(from(l in Light, where: l.bridge_id == ^bridge_id and l.source == ^source))
    |> Enum.reduce(%{}, fn light, acc -> Map.put(acc, light.source_id, light) end)
  end

  def groups_by_source_id(bridge_id, source) do
    Repo.all(from(g in Group, where: g.bridge_id == ^bridge_id and g.source == ^source))
    |> Enum.reduce(%{}, fn group, acc -> Map.put(acc, group.source_id, group) end)
  end

  defp index_by_metadata(lights, source, key) do
    lights
    |> Enum.filter(fn light -> light.source == source end)
    |> Enum.reduce(%{}, fn light, acc ->
      value = metadata_value(light.metadata, key)

      if is_binary(value) do
        Map.put(acc, value, light)
      else
        acc
      end
    end)
  end

  defp metadata_value(metadata, key) when is_map(metadata) do
    case key do
      "mac" -> Map.get(metadata, key) || Map.get(metadata, :mac)
      "serial" -> Map.get(metadata, key) || Map.get(metadata, :serial)
      _ -> Map.get(metadata, key)
    end
  end

  defp metadata_value(_metadata, _key), do: nil

  defp index_by_source_id(lights, source) do
    lights
    |> Enum.filter(fn light -> light.source == source end)
    |> Enum.reduce(%{}, fn light, acc ->
      if is_binary(light.source_id) do
        Map.put(acc, light.source_id, light)
      else
        acc
      end
    end)
  end
end
