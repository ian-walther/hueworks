defmodule Hueworks.HomeAssistant.InventoryTest do
  use ExUnit.Case, async: true

  alias Hueworks.HomeAssistant.Inventory

  test "separates native wrappers from HA-only entities and summarizes supported sources" do
    raw = %{
      config_entries: [
        %{entry_id: "hue-entry", domain: "hue", title: "Hue Bridge"},
        %{entry_id: "zha-entry", domain: "zha", title: "ZHA"},
        %{entry_id: "mqtt-entry", domain: "mqtt", title: "MQTT"}
      ],
      floors: [],
      areas: []
    }

    normalized = %{
      external_spaces: [],
      lights: [
        light("light.hue", "hue", "hue", "hue-entry"),
        light("light.template", "template", "unknown", "template-entry"),
        light("light.mqtt", "mqtt", "unknown", "mqtt-entry")
      ],
      groups: []
    }

    inventory = Inventory.from_snapshot(raw, normalized)

    assert Enum.map(inventory.native_wrappers, & &1.source_id) == ["light.hue", "light.mqtt"]
    assert Enum.map(inventory.ha_only_entities, & &1.source_id) == ["light.template"]

    assert Enum.any?(inventory.native_sources, fn source ->
             source.kind == :hue and source.confidence == :confirmed and
               source.entity_count == 1
           end)

    assert Enum.any?(inventory.native_sources, fn source ->
             source.kind == :z2m and source.confidence == :possible
           end)
  end

  test "reports unavailable optional registry capabilities without failing inventory" do
    inventory = Inventory.from_snapshot(%{}, %{lights: [], groups: [], external_spaces: []})

    assert :floor_registry_unavailable in inventory.warnings
    assert :config_entries_unavailable in inventory.warnings
    assert :no_spatial_inventory in inventory.warnings
  end

  defp light(source_id, platform, source, config_entry_id) do
    %{
      source_id: source_id,
      metadata: %{
        "platform" => platform,
        "source" => source,
        "config_entry_id" => config_entry_id
      }
    }
  end
end
