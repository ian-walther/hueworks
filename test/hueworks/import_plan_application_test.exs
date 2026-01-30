defmodule Hueworks.Import.PlanApplicationTest do
  use Hueworks.DataCase, async: false

  alias Hueworks.Import.Materialize
  alias Hueworks.Repo
  alias Hueworks.Schemas.{Bridge, Group, Light, Room}

  defp insert_bridge(attrs \\ %{}) do
    defaults = %{
      type: :hue,
      name: "Hue Bridge",
      host: "10.0.0.200",
      credentials: %{"api_key" => "key"},
      import_complete: false,
      enabled: true
    }

    Repo.insert!(struct(Bridge, Map.merge(defaults, attrs)))
  end

  test "room skip plan does not create a new room" do
    bridge = insert_bridge()

    normalized = %{
      rooms: [
        %{
          source: :hue,
          source_id: "1",
          name: "Office",
          normalized_name: "office",
          metadata: %{}
        }
      ],
      lights: [],
      groups: [],
      memberships: %{}
    }

    plan = %{
      "rooms" => %{
        "1" => %{"action" => "skip"}
      },
      "lights" => %{},
      "groups" => %{}
    }

    assert :ok == Materialize.materialize(bridge, normalized, plan)
    assert Repo.aggregate(Room, :count) == 0
  end

  test "room merge plan assigns lights to target room" do
    bridge = insert_bridge(%{host: "10.0.0.201"})
    target_room = Repo.insert!(%Room{name: "Existing"})

    normalized = %{
      rooms: [
        %{
          source: :hue,
          source_id: "1",
          name: "Office",
          normalized_name: "office",
          metadata: %{}
        }
      ],
      lights: [
        %{
          source: :hue,
          source_id: "1",
          name: "Lamp",
          room_source_id: "1",
          capabilities: %{},
          identifiers: %{},
          metadata: %{}
        }
      ],
      groups: [
        %{
          source: :hue,
          source_id: "2",
          name: "Office Group",
          room_source_id: "1",
          type: "group",
          capabilities: %{},
          metadata: %{}
        }
      ],
      memberships: %{}
    }

    plan = %{
      "rooms" => %{
        "1" => %{"action" => "merge", "target_room_id" => Integer.to_string(target_room.id)}
      },
      "lights" => %{"1" => true},
      "groups" => %{"2" => true}
    }

    assert :ok == Materialize.materialize(bridge, normalized, plan)

    light = Repo.get_by!(Light, bridge_id: bridge.id, source_id: "1")
    group = Repo.get_by!(Group, bridge_id: bridge.id, source_id: "2")

    assert light.room_id == target_room.id
    assert group.room_id == target_room.id
    assert Repo.aggregate(Room, :count) == 1
  end

  test "room skip does not delete existing room" do
    bridge = insert_bridge(%{host: "10.0.0.202"})
    existing_room = Repo.insert!(%Room{name: "Office"})

    normalized = %{
      rooms: [
        %{
          source: :hue,
          source_id: "1",
          name: "Office",
          normalized_name: "office",
          metadata: %{}
        }
      ],
      lights: [],
      groups: [],
      memberships: %{}
    }

    plan = %{
      "rooms" => %{
        "1" => %{"action" => "skip"}
      },
      "lights" => %{},
      "groups" => %{}
    }

    assert :ok == Materialize.materialize(bridge, normalized, plan)
    assert Repo.get(Room, existing_room.id)
    assert Repo.aggregate(Room, :count) == 1
  end
end
