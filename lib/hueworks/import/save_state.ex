defmodule Hueworks.Import.SaveState do
  @moduledoc """
  Export and apply light/group state overrides.
  """

  alias Hueworks.Repo
  alias Hueworks.Schemas.Bridge
  alias Hueworks.Schemas.Group
  alias Hueworks.Schemas.Light

  @default_path "exports/save_state.json"

  def default_path, do: @default_path

  def export(path \\ @default_path) do
    bridges = bridge_index()
    lights = Repo.all(Light)
    groups = Repo.all(Group)

    payload = %{
      exported_at: DateTime.utc_now() |> DateTime.to_iso8601(),
      lights: export_entities(:light, lights, bridges),
      groups: export_entities(:group, groups, bridges)
    }

    path |> Path.dirname() |> File.mkdir_p!()
    File.write!(path, Jason.encode!(payload, pretty: true))
    {:ok, path}
  end

  def load(path \\ @default_path) do
    if File.exists?(path) do
      data =
        path
        |> File.read!()
        |> Jason.decode!()

      cond do
        is_map(data["lights"]) or is_map(data["groups"]) ->
          %{
            lights: normalize_override_map(data["lights"] || %{}),
            groups: normalize_override_map(data["groups"] || %{})
          }

        is_list(data["entries"]) ->
          legacy_entries = Enum.map(data["entries"], &normalize_entry/1)
          legacy_overrides(legacy_entries)

        true ->
          %{lights: %{}, groups: %{}}
      end
    else
      %{lights: %{}, groups: %{}}
    end
  end

  def apply(%{lights: lights, groups: groups})
      when is_map(lights) and is_map(groups) do
    bridges = bridge_index()

    Repo.all(Light)
    |> Enum.each(&apply_overrides(:light, &1, bridges, lights))

    Repo.all(Group)
    |> Enum.each(&apply_overrides(:group, &1, bridges, groups))
  end

  defp bridge_index do
    Repo.all(Bridge)
    |> Enum.reduce(%{}, fn bridge, acc ->
      Map.put(acc, bridge.id, %{type: bridge.type, host: bridge.host})
    end)
  end

  defp export_entities(type, entities, bridges) do
    Enum.reduce(entities, %{}, fn entity, acc ->
      key = to_string(entity.source_id)
      entry = entry_for(type, entity, bridges)
      put_override(acc, key, entry)
    end)
    |> normalize_override_output()
  end

  defp entry_for(type, entity, bridges) do
    bridge = Map.get(bridges, entity.bridge_id, %{type: nil, host: nil})

    %{
      type: to_string(type),
      source: to_string(entity.source),
      source_id: entity.source_id,
      name: entity.name,
      bridge_type: to_string(bridge.type || ""),
      bridge_host: bridge.host || "",
      display_name: Map.get(entity, :display_name),
      enabled: Map.get(entity, :enabled),
      actual_min_kelvin: Map.get(entity, :actual_min_kelvin),
      actual_max_kelvin: Map.get(entity, :actual_max_kelvin),
      extended_kelvin_range: Map.get(entity, :extended_kelvin_range)
    }
  end

  defp normalize_entry(entry) when is_map(entry) do
    %{
      type: entry["type"] || entry[:type],
      source: entry["source"] || entry[:source],
      source_id: entry["source_id"] || entry[:source_id],
      bridge_host: entry["bridge_host"] || entry[:bridge_host],
      display_name: entry["display_name"] || entry[:display_name],
      enabled: entry["enabled"],
      actual_min_kelvin: entry["actual_min_kelvin"],
      actual_max_kelvin: entry["actual_max_kelvin"],
      extended_kelvin_range: entry["extended_kelvin_range"]
    }
  end

  defp normalize_entry(_entry), do: %{}

  defp legacy_overrides(entries) do
    Enum.reduce(entries, %{lights: %{}, groups: %{}}, fn entry, acc ->
      key = to_string(entry.source_id)
      type = to_string(entry.type)
      override = Map.merge(entry, %{enabled: false})

      case type do
        "light" -> %{acc | lights: put_override(acc.lights, key, override)}
        "group" -> %{acc | groups: put_override(acc.groups, key, override)}
        _ -> acc
      end
    end)
  end

  defp normalize_override_map(map) when is_map(map) do
    Enum.reduce(map, %{}, fn {source_id, value}, acc ->
      entries =
        case value do
          list when is_list(list) -> Enum.map(list, &normalize_entry/1)
          entry when is_map(entry) -> [normalize_entry(entry)]
          _ -> []
        end

      Map.put(acc, to_string(source_id), entries)
    end)
  end

  defp normalize_override_output(map) do
    Enum.reduce(map, %{}, fn {source_id, entries}, acc ->
      value = if length(entries) == 1, do: List.first(entries), else: entries
      Map.put(acc, source_id, value)
    end)
  end

  defp put_override(map, key, entry) do
    Map.update(map, key, [entry], fn entries -> entries ++ [entry] end)
  end

  defp apply_overrides(type, entity, bridges, overrides) do
    key = to_string(entity.source_id)
    bridge = Map.get(bridges, entity.bridge_id, %{host: "", type: ""})

    entries =
      overrides
      |> Map.get(key, [])
      |> Enum.filter(&match_override?(&1, type, entity, bridge))

    case entries do
      [entry | _] ->
        attrs = override_attrs(entry)
        changeset = Ecto.Changeset.change(entity, attrs)
        Repo.update!(changeset)

      [] ->
        :ok
    end
  end

  defp match_override?(entry, type, entity, bridge) do
    entry_type = to_string(entry.type || "")
    entry_source = to_string(entry.source || "")
    entry_host = to_string(entry.bridge_host || "")

    entry_type == to_string(type) and entry_source == to_string(entity.source) and
      entry_host == to_string(bridge.host)
  end

  defp override_attrs(entry) do
    %{
      display_name: Map.get(entry, :display_name),
      enabled: Map.get(entry, :enabled),
      actual_min_kelvin: Map.get(entry, :actual_min_kelvin),
      actual_max_kelvin: Map.get(entry, :actual_max_kelvin),
      extended_kelvin_range: Map.get(entry, :extended_kelvin_range)
    }
  end
end
