defmodule Hueworks.Import.DisabledList do
  @moduledoc """
  Export and apply disabled light/group lists.
  """

  import Ecto.Query, only: [from: 2]

  alias Hueworks.Repo
  alias Hueworks.Schemas.Bridge
  alias Hueworks.Schemas.Group
  alias Hueworks.Schemas.Light

  @default_path "exports/disabled_entities.json"

  def default_path, do: @default_path

  def export(path \\ @default_path) do
    bridges = bridge_index()
    lights = Repo.all(from(l in Light, where: l.enabled == false))
    groups = Repo.all(from(g in Group, where: g.enabled == false))

    entries =
      lights
      |> Enum.map(&entry_for(:light, &1, bridges))
      |> Kernel.++(Enum.map(groups, &entry_for(:group, &1, bridges)))
      |> Enum.sort_by(&{&1.type, &1.source, &1.bridge_host, &1.source_id})

    payload = %{
      exported_at: DateTime.utc_now() |> DateTime.to_iso8601(),
      entries: entries
    }

    path |> Path.dirname() |> File.mkdir_p!()
    File.write!(path, Jason.encode!(payload, pretty: true))
    {:ok, path}
  end

  def load(path \\ @default_path) do
    if File.exists?(path) do
      path
      |> File.read!()
      |> Jason.decode!()
      |> Map.get("entries", [])
      |> Enum.map(&normalize_entry/1)
    else
      []
    end
  end

  def apply(entries) when is_list(entries) do
    bridges = bridge_index()
    disabled = entries |> Enum.map(&entry_key/1) |> MapSet.new()

    lights = Repo.all(Light)
    groups = Repo.all(Group)

    update_entities(lights, :light, bridges, disabled)
    update_entities(groups, :group, bridges, disabled)
  end

  defp update_entities(entities, type, bridges, disabled) do
    Enum.each(entities, fn entity ->
      key = entity_key(type, entity, bridges)
      should_disable = MapSet.member?(disabled, key)

      if entity.enabled == should_disable do
        changeset = entity |> Ecto.Changeset.change(enabled: not should_disable)
        Repo.update!(changeset)
      end
    end)
  end

  defp bridge_index do
    Repo.all(Bridge)
    |> Enum.reduce(%{}, fn bridge, acc ->
      Map.put(acc, bridge.id, %{type: bridge.type, host: bridge.host})
    end)
  end

  defp entry_for(type, entity, bridges) do
    bridge = Map.get(bridges, entity.bridge_id, %{type: nil, host: nil})

    %{
      type: to_string(type),
      source: to_string(entity.source),
      source_id: entity.source_id,
      name: entity.name,
      bridge_type: to_string(bridge.type || ""),
      bridge_host: bridge.host || ""
    }
  end

  defp normalize_entry(entry) when is_map(entry) do
    %{
      type: entry["type"] || entry[:type],
      source: entry["source"] || entry[:source],
      source_id: entry["source_id"] || entry[:source_id],
      bridge_host: entry["bridge_host"] || entry[:bridge_host]
    }
  end

  defp normalize_entry(_entry), do: %{}

  defp entry_key(%{type: type, source: source, source_id: source_id, bridge_host: bridge_host}) do
    {to_string(type), to_string(source), to_string(source_id), to_string(bridge_host)}
  end

  defp entity_key(type, entity, bridges) do
    bridge = Map.get(bridges, entity.bridge_id, %{host: ""})
    {to_string(type), to_string(entity.source), to_string(entity.source_id), to_string(bridge.host)}
  end
end
