defmodule Hueworks.Import.NormalizeTest do
  use ExUnit.Case, async: true

  alias Hueworks.Import.Normalize
  alias Hueworks.Schemas.Bridge

  test "normalizes Hue raw data into rooms, groups, and lights" do
    raw = load_fixture("hue_raw.json")

    bridge = %Bridge{id: 1, type: :hue, name: "Test Bridge", host: "10.0.0.1"}
    normalized = Normalize.normalize(bridge, raw)

    assert normalized.schema_version == 1
    assert normalized.bridge.type == :hue
    assert length(normalized.rooms) == 1

    [room] = normalized.rooms
    assert room.source_id == "1"
    assert room.name == "Office"
    assert room.normalized_name == "office"

    assert length(normalized.lights) == 2
    ceiling = Enum.find(normalized.lights, &(&1.source_id == "1"))
    assert ceiling.room_source_id == "1"
    assert ceiling.capabilities.reported_kelvin_min == 2000
    assert ceiling.capabilities.reported_kelvin_max == 6536

    group = Enum.find(normalized.groups, &(&1.source_id == "2"))
    assert group.type == "zone"
    assert Enum.any?(normalized.memberships.group_lights, &(&1.group_source_id == "2"))
  end

  test "normalizes Home Assistant raw data into rooms, groups, and lights" do
    raw = load_fixture("ha_raw.json")

    bridge = %Bridge{id: 2, type: :ha, name: "HA", host: "10.0.0.2"}
    normalized = Normalize.normalize(bridge, raw)

    assert length(normalized.rooms) == 1
    [room] = normalized.rooms
    assert room.source_id == "office"
    assert room.name == "Office"

    [light] = normalized.lights
    assert light.source_id == "light.office_lamp"
    assert light.room_source_id == "office"
    assert light.capabilities.color_temp
    assert light.capabilities.reported_kelvin_min == 2000
    assert light.capabilities.reported_kelvin_max == 6500
    assert light.identifiers["mac"] == "00:aa:bb:cc:dd:ee"

    [group] = normalized.groups
    assert group.source_id == "light.office_group"
    assert group.room_source_id == "office"
    assert Enum.any?(normalized.memberships.group_lights, &(&1.group_source_id == group.source_id))
    assert Enum.any?(normalized.memberships.room_groups, &(&1.group_source_id == group.source_id))
  end

  test "normalizes Caseta raw data into rooms and lights" do
    raw = load_fixture("caseta_raw.json")

    bridge = %Bridge{id: 3, type: :caseta, name: "Caseta", host: "10.0.0.3"}
    normalized = Normalize.normalize(bridge, raw)

    assert length(normalized.rooms) == 1
    [room] = normalized.rooms
    assert room.source_id == "area_1"
    assert room.name == "Living room"

    [light] = normalized.lights
    assert light.source_id == "1"
    assert light.capabilities.brightness
    refute light.capabilities.color
    assert light.identifiers["serial"] == "12345678"
  end

  defp load_fixture(name) do
    path = Path.join(["test", "fixtures", "normalize", name])
    path |> File.read!() |> Jason.decode!()
  end
end
