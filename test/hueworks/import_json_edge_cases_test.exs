defmodule Hueworks.Import.JsonEdgeCasesTest do
  use Hueworks.DataCase, async: false

  alias Hueworks.Import.{Materialize, Normalize}
  alias Hueworks.Repo
  alias Hueworks.Schemas.{Bridge, Group, Light, Room}

  test "normalize tolerates partial Hue payloads" do
    raw = %{
      "lights" => %{
        "1" => %{"name" => nil, "capabilities" => %{}, "state" => %{}}
      },
      "groups" => %{}
    }

    bridge = %Bridge{id: 1, type: :hue, name: "Hue", host: "10.0.0.1"}
    normalized = Normalize.normalize(bridge, raw)

    assert length(normalized.lights) == 1
    [light] = normalized.lights
    assert light.name == "Hue Light 1"
    assert light.source_id == "1"
    assert light.room_source_id == nil
    assert light.capabilities.reported_kelvin_min == nil
    assert light.capabilities.reported_kelvin_max == nil
  end

  test "normalize tolerates partial Home Assistant payloads" do
    raw = %{
      "areas" => [],
      "device_registry" => [],
      "light_entities" => [
        %{"entity_id" => "light.minimal"}
      ],
      "group_entities" => [],
      "light_states" => %{},
      "zha_groups" => []
    }

    bridge = %Bridge{id: 2, type: :ha, name: "HA", host: "10.0.0.2"}
    normalized = Normalize.normalize(bridge, raw)

    assert length(normalized.lights) == 1
    [light] = normalized.lights
    assert light.source_id == "light.minimal"
    assert light.name == "light.minimal"
    assert light.classification == "light"
  end

  test "normalize tolerates partial Caseta payloads" do
    raw = %{
      "lights" => [
        %{"zone_id" => "1", "name" => "Caseta Light"}
      ],
      "groups" => []
    }

    bridge = %Bridge{id: 3, type: :caseta, name: "Caseta", host: "10.0.0.3"}
    normalized = Normalize.normalize(bridge, raw)

    assert length(normalized.rooms) == 0
    assert length(normalized.lights) == 1
    [light] = normalized.lights
    assert light.source_id == "1"
    assert light.room_source_id == nil
  end

  test "materialize skips entities missing source_id" do
    bridge =
      %Bridge{}
      |> Bridge.changeset(%{
        type: :ha,
        name: "HA",
        host: "10.0.0.4",
        credentials: %{"token" => "token"},
        import_complete: false,
        enabled: true
      })
      |> Repo.insert!()

    normalized = %{
      rooms: [%{source_id: nil, name: "Room"}],
      lights: [
        %{
          source: :ha,
          source_id: nil,
          name: "Light",
          room_source_id: nil,
          capabilities: %{},
          identifiers: %{},
          metadata: %{}
        }
      ],
      groups: [
        %{
          source: :ha,
          source_id: nil,
          name: "Group",
          room_source_id: nil,
          type: "group",
          capabilities: %{},
          metadata: %{}
        }
      ],
      memberships: %{}
    }

    assert :ok == Materialize.materialize(bridge, normalized)
    assert Repo.aggregate(Room, :count) == 0
    assert Repo.aggregate(Light, :count) == 0
    assert Repo.aggregate(Group, :count) == 0
  end
end
