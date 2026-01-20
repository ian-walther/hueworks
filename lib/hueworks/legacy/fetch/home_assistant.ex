defmodule Hueworks.Legacy.Fetch.HomeAssistant do
  @moduledoc """
  Fetch minimal Home Assistant data needed for import.
  """

  import Ecto.Query, only: [from: 2]

  alias Hueworks.Legacy.Fetch.HomeAssistant.Client
  alias Hueworks.Schemas.Bridge
  alias Hueworks.Repo

  def fetch do
    bridge = load_bridge(:ha)
    token = bridge.credentials["token"]

    if invalid_credential?(token) do
      raise "Missing Home Assistant token for bridge #{bridge.name} (#{bridge.host})"
    end

    IO.puts("Connecting to Home Assistant...")
    {:ok, pid} = Client.connect(bridge.host, token)

    IO.puts("Fetching entity registry...")
    entity_registry = get_entity_registry(pid)

    IO.puts("Fetching device registry...")
    device_registry = get_device_registry(pid)

    IO.puts("Fetching light states...")
    states = get_states(pid)
    zone_by_entity_id = zone_by_entity_id(states)
    group_members_by_entity_id = group_members_by_entity_id(states)
    temp_range_by_entity_id = temp_range_by_entity_id(states)
    color_modes_by_entity_id = supported_color_modes_by_entity_id(states)

    light_entities =
      entity_registry
      |> Enum.filter(fn entry ->
        String.starts_with?(entry["entity_id"], "light.")
      end)
      |> merge_entity_registry(entity_registry)
      |> merge_device_registry(device_registry)
      |> merge_zone_ids(zone_by_entity_id)
      |> merge_temp_ranges(temp_range_by_entity_id)
      |> merge_color_modes(color_modes_by_entity_id)
      |> merge_group_members(group_members_by_entity_id)
      |> tag_entity_sources()
      |> simplify_lights()

    group_entities =
      entity_registry
      |> Enum.filter(fn entry ->
        String.starts_with?(entry["entity_id"], "light.") and
          entry["platform"] in ["group", "light_group"]
      end)
      |> simplify_groups(group_members_by_entity_id)

    %{
      host: bridge.host,
      light_entities: light_entities,
      group_entities: group_entities,
      light_count: length(light_entities),
      total_entity_count: length(entity_registry),
      exported_at: DateTime.utc_now() |> DateTime.to_iso8601()
    }
  end

  defp get_entity_registry(pid) do
    case request(pid, "config/entity_registry/list", %{}) do
      {:ok, entities} -> entities
      {:error, _reason} -> []
    end
  end

  defp get_device_registry(pid) do
    case request(pid, "config/device_registry/list", %{}) do
      {:ok, devices} -> devices
      {:error, _reason} -> []
    end
  end

  defp get_states(pid) do
    case request(pid, "get_states", %{}) do
      {:ok, states} when is_list(states) -> states
      _ -> []
    end
  end

  defp zone_by_entity_id(states) do
    states
    |> Enum.filter(&is_map/1)
    |> Enum.filter(fn state -> String.starts_with?(state["entity_id"], "light.") end)
    |> Enum.reduce(%{}, fn state, acc ->
      zone_id = get_in(state, ["attributes", "zone_id"])

      if zone_id do
        Map.put(acc, state["entity_id"], zone_id)
      else
        acc
      end
    end)
  end

  defp group_members_by_entity_id(states) do
    states
    |> Enum.filter(&is_map/1)
    |> Enum.filter(fn state -> String.starts_with?(state["entity_id"], "light.") end)
    |> Enum.reduce(%{}, fn state, acc ->
      members = get_in(state, ["attributes", "entity_id"])

      if is_list(members) do
        Map.put(acc, state["entity_id"], members)
      else
        acc
      end
    end)
  end

  defp temp_range_by_entity_id(states) do
    states
    |> Enum.filter(&is_map/1)
    |> Enum.filter(fn state -> String.starts_with?(state["entity_id"], "light.") end)
    |> Enum.reduce(%{}, fn state, acc ->
      attrs = state["attributes"] || %{}
      min_mireds = Map.get(attrs, "min_mireds")
      max_mireds = Map.get(attrs, "max_mireds")
      min_kelvin = Map.get(attrs, "min_color_temp_kelvin")
      max_kelvin = Map.get(attrs, "max_color_temp_kelvin")

      range =
        cond do
          is_number(min_kelvin) and is_number(max_kelvin) ->
            %{
              "min_kelvin" => round(min_kelvin),
              "max_kelvin" => round(max_kelvin)
            }

          is_number(min_mireds) and is_number(max_mireds) ->
            %{
              "min_mireds" => round(min_mireds),
              "max_mireds" => round(max_mireds)
            }

          true ->
            nil
        end

      if range do
        Map.put(acc, state["entity_id"], range)
      else
        acc
      end
    end)
  end

  defp merge_entity_registry(light_entities, entity_registry) do
    registry_by_entity_id =
      entity_registry
      |> Enum.filter(&is_map/1)
      |> Map.new(fn entity -> {entity["entity_id"], entity} end)

    Enum.map(light_entities, fn entity ->
      registry_entry = Map.get(registry_by_entity_id, entity["entity_id"])
      Map.put(entity, "registry", registry_entry)
    end)
  end

  defp merge_device_registry(light_entities, device_registry) do
    devices_by_id =
      device_registry
      |> Enum.filter(&is_map/1)
      |> Map.new(fn device -> {device["id"], device} end)

    Enum.map(light_entities, fn entity ->
      device_id = entity["device_id"]
      device = if device_id, do: Map.get(devices_by_id, device_id), else: nil
      Map.put(entity, "device", device)
    end)
  end

  defp merge_zone_ids(light_entities, zone_by_entity_id) do
    Enum.map(light_entities, fn entity ->
      zone_id = Map.get(zone_by_entity_id, entity["entity_id"])
      if zone_id, do: Map.put(entity, "zone_id", zone_id), else: entity
    end)
  end

  defp merge_temp_ranges(light_entities, temp_range_by_entity_id) do
    Enum.map(light_entities, fn entity ->
      range = Map.get(temp_range_by_entity_id, entity["entity_id"])
      if range, do: Map.put(entity, "temp_range", range), else: entity
    end)
  end

  defp supported_color_modes_by_entity_id(states) do
    states
    |> Enum.filter(&is_map/1)
    |> Enum.filter(fn state -> String.starts_with?(state["entity_id"], "light.") end)
    |> Enum.reduce(%{}, fn state, acc ->
      modes = get_in(state, ["attributes", "supported_color_modes"])

      if is_list(modes) do
        Map.put(acc, state["entity_id"], modes)
      else
        acc
      end
    end)
  end

  defp merge_color_modes(light_entities, color_modes_by_entity_id) do
    Enum.map(light_entities, fn entity ->
      modes = Map.get(color_modes_by_entity_id, entity["entity_id"])
      if modes, do: Map.put(entity, "supported_color_modes", modes), else: entity
    end)
  end

  defp merge_group_members(light_entities, group_members_by_entity_id) do
    Enum.map(light_entities, fn entity ->
      members = Map.get(group_members_by_entity_id, entity["entity_id"])
      if members, do: Map.put(entity, "members", members), else: entity
    end)
  end

  defp tag_entity_sources(light_entities) do
    Enum.map(light_entities, fn entity ->
      source =
        entity_source(
          get_in(entity, ["registry", "platform"]),
          entity["device"]
        )

      Map.put(entity, "source", source)
    end)
  end

  defp entity_source(platform, device) do
    case platform do
      "hue" -> "hue"
      "lutron_caseta" -> "lutron"
      _ -> source_from_device(device) || "unknown"
    end
  end

  defp source_from_device(device) do
    identifiers = device_identifiers(device)

    cond do
      Enum.any?(identifiers, &match?({"hue", _}, &1)) -> "hue"
      Enum.any?(identifiers, &match?({"lutron_caseta", _}, &1)) -> "lutron"
      true -> nil
    end
  end

  defp device_identifiers(%{"identifiers" => identifiers}) when is_list(identifiers) do
    Enum.map(identifiers, fn
      [domain, value] -> {domain, value}
      {domain, value} -> {domain, value}
      _ -> nil
    end)
    |> Enum.filter(& &1)
  end

  defp device_identifiers(_device), do: []

  defp simplify_lights(light_entities) do
    Enum.map(light_entities, fn entity ->
      registry = entity["registry"] || %{}
      device = entity["device"]

      %{
        entity_id: entity["entity_id"],
        name: registry["name"] || registry["original_name"],
        unique_id: registry["unique_id"],
        platform: registry["platform"],
        device_id: entity["device_id"],
        zone_id: entity["zone_id"],
        source: entity["source"],
        temp_range: entity["temp_range"],
        supported_color_modes: entity["supported_color_modes"],
        members: entity["members"],
        device: simplify_device(device)
      }
    end)
  end

  defp simplify_device(device) when is_map(device) do
    %{
      id: device["id"],
      name: device["name"],
      manufacturer: device["manufacturer"],
      model: device["model"],
      identifiers: device["identifiers"],
      connections: device["connections"],
      via_device_id: device["via_device_id"]
    }
  end

  defp simplify_device(_device), do: nil

  defp simplify_groups(groups, group_members_by_entity_id) do
    Enum.map(groups, fn entity ->
      members = Map.get(group_members_by_entity_id, entity["entity_id"], [])

      %{
        entity_id: entity["entity_id"],
        name: entity["name"] || entity["original_name"],
        platform: entity["platform"],
        members: members
      }
    end)
  end

  defp request(pid, type, params) do
    ref = make_ref()

    WebSockex.cast(pid, {:request, ref, self(), type, params, & &1})

    receive do
      {:response, ^ref, result} -> result
    after
      10_000 -> {:error, :timeout}
    end
  end

  defp load_bridge(type) do
    case Repo.all(from(b in Bridge, where: b.type == ^type and b.enabled == true)) do
      [bridge] ->
        bridge

      [] ->
        raise "No enabled #{type} bridge found. Seed bridges before fetching."

      _ ->
        raise "Multiple enabled #{type} bridges found. Only one is supported for now."
    end
  end

  defp invalid_credential?(value) do
    not is_binary(value) or value == "" or value == "CHANGE_ME"
  end
end
