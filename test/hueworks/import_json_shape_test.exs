defmodule Hueworks.Import.JsonShapeTest do
  use Hueworks.DataCase, async: false

  alias Hueworks.Import.{Materialize, Normalize}
  alias Hueworks.Repo
  alias Hueworks.Schemas.{Bridge, Light, Room}

  test "normalize handles unexpected HA shapes without crashing" do
    raw = %{
      "areas" => "not-a-list",
      "device_registry" => %{"bad" => true},
      "light_entities" => [%{"entity_id" => "light.one", "device" => "bad"}],
      "group_entities" => [%{"entity_id" => "light.group", "members" => "bad"}],
      "light_states" => "bad",
      "zha_groups" => [%{"group_id" => "bad", "members" => "bad"}]
    }

    bridge = %Bridge{id: 10, type: :ha, name: "HA", host: "10.0.0.10"}
    normalized = Normalize.normalize(bridge, raw)

    assert normalized.lights != nil
    assert normalized.groups != nil
  end

  test "normalize handles unexpected Hue shapes without crashing" do
    raw = %{
      "lights" => ["not-a-map"],
      "groups" => ["not-a-map"]
    }

    bridge = %Bridge{id: 11, type: :hue, name: "Hue", host: "10.0.0.11"}
    normalized = Normalize.normalize(bridge, raw)

    assert normalized.lights == []
    assert normalized.groups == []
  end

  test "normalize handles unexpected Caseta shapes without crashing" do
    raw = %{
      "lights" => %{"bad" => true},
      "groups" => %{"bad" => true}
    }

    bridge = %Bridge{id: 12, type: :caseta, name: "Caseta", host: "10.0.0.12"}
    normalized = Normalize.normalize(bridge, raw)

    assert normalized.rooms == []
    assert normalized.lights == []
  end

  test "materialize tolerates invalid room_source_id references" do
    bridge =
      %Bridge{}
      |> Bridge.changeset(%{
        type: :ha,
        name: "HA",
        host: "10.0.0.13",
        credentials: %{"token" => "token"},
        import_complete: false,
        enabled: true
      })
      |> Repo.insert!()

    normalized = %{
      rooms: [
        %{source_id: "room-1", name: "Office"}
      ],
      lights: [
        %{
          source: :ha,
          source_id: "light.one",
          name: "Light One",
          room_source_id: "room-does-not-exist",
          capabilities: %{},
          identifiers: %{},
          metadata: %{}
        }
      ],
      groups: [],
      memberships: %{}
    }

    assert :ok == Materialize.materialize(bridge, normalized)

    light = Repo.get_by!(Light, bridge_id: bridge.id, source_id: "light.one")
    assert light.room_id == nil
    assert Repo.aggregate(Room, :count) == 1
  end
end
