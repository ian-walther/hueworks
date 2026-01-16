defmodule Hueworks.Import.Persist do
  @moduledoc """
  Shared persistence helpers for importing bridges and lights.
  """

  alias Hueworks.Bridges.Bridge
  alias Hueworks.Lights.Light
  alias Hueworks.Repo

  def get_bridge!(type, host) do
    Repo.get_by!(Bridge, type: type, host: host)
  end

  def upsert_light(attrs) do
    changeset = Light.changeset(%Light{}, attrs)

    Repo.insert(
      changeset,
      on_conflict: {:replace, [:name, :metadata, :enabled, :parent_id, :updated_at]},
      conflict_target: [:bridge_id, :source_id]
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
