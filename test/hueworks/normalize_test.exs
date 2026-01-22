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

    assert length(normalized.rooms) == 2
    [office] = Enum.filter(normalized.rooms, &(&1.source_id == "office"))
    assert office.name == "Office"

    light = Enum.find(normalized.lights, &(&1.source_id == "light.office_lamp"))
    assert light.room_source_id == "office"
    assert light.capabilities.color_temp
    assert light.capabilities.reported_kelvin_min == 2000
    assert light.capabilities.reported_kelvin_max == 6500
    assert light.identifiers["mac"] == "00:aa:bb:cc:dd:ee"

    kitchen = Enum.find(normalized.lights, &(&1.source_id == "light.kitchen_lamp"))
    assert kitchen.room_source_id == "kitchen"

    refute Enum.any?(normalized.lights, &(&1.source_id == "light.office_group"))
    refute Enum.any?(normalized.lights, &(&1.source_id == "light.office_room"))
    refute Enum.any?(normalized.lights, &(&1.source_id == "light.zha_group"))
    refute Enum.any?(normalized.lights, &(&1.source_id == "light.zha_group_members"))

    missing_state = Enum.find(normalized.lights, &(&1.source_id == "light.zha_group_missing"))
    assert missing_state.metadata["unique_id"] == "zha-light-2"

    hue_group = Enum.find(normalized.groups, &(&1.source_id == "light.office_room"))
    assert hue_group.metadata["device_model"] == "Room"
    assert hue_group.metadata["members"] == ["light.office_lamp"]

    zha_group = Enum.find(normalized.groups, &(&1.source_id == "light.zha_group"))
    assert zha_group.metadata["unique_id"] == "light_zha_group_0x0001"
    assert zha_group.metadata["members"] == ["light.office_lamp"]

    zha_group_members = Enum.find(normalized.groups, &(&1.source_id == "light.zha_group_members"))
    assert zha_group_members.metadata["members"] == ["light.office_lamp", "light.kitchen_lamp"]

    group = Enum.find(normalized.groups, &(&1.source_id == "light.office_group"))
    assert group.room_source_id == "office"
    assert Enum.any?(normalized.memberships.group_lights, &(&1.group_source_id == group.source_id))
    assert Enum.any?(normalized.memberships.room_groups, &(&1.group_source_id == group.source_id))

    mixed_group = Enum.find(normalized.groups, &(&1.source_id == "light.mixed_group"))
    assert mixed_group.room_source_id == nil

    refute Enum.any?(normalized.groups, &(&1.source_id == "light.zha_group_missing"))
  end

  test "normalizes Home Assistant raw data with template filtering options" do
    raw = load_fixture("ha_raw.json")

    bridge = %Bridge{id: 2, type: :ha, name: "HA", host: "10.0.0.2"}
    normalized = Normalize.normalize(bridge, raw, %{exclude_template_lights: true})

    refute Enum.any?(normalized.lights, &(&1.source_id == "light.bar_lower_accent_light"))

    template_group =
      Enum.find(normalized.groups, &(&1.source_id == "light.template_group"))

    assert template_group.metadata["members"] == ["light.office_lamp"]

    assert Enum.all?(normalized.memberships.group_lights, fn membership ->
             membership.light_source_id != "light.bar_lower_accent_light"
           end)
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
