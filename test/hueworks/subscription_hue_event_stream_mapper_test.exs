defmodule Hueworks.Subscription.HueEventStream.MapperTest do
  use Hueworks.DataCase, async: false

  alias Hueworks.Control.State
  alias Hueworks.Repo
  alias Hueworks.Schemas.{Group, GroupLight, Light, Room}
  alias Hueworks.Subscription.HueEventStream.Mapper

  setup do
    if :ets.whereis(:hueworks_control_state) != :undefined do
      :ets.delete_all_objects(:hueworks_control_state)
    end

    :ok
  end

  test "grouped_light event fans out state updates to member lights" do
    room = Repo.insert!(%Room{name: "Hue Room"})

    bridge =
      insert_bridge!(%{
        type: :hue,
        name: "Hue",
        host: "10.0.0.40",
        credentials: %{"api_key" => "key"},
        enabled: true
      })

    light_a =
      Repo.insert!(%Light{
        name: "A",
        source: :hue,
        source_id: "11",
        bridge_id: bridge.id,
        room_id: room.id
      })

    light_b =
      Repo.insert!(%Light{
        name: "B",
        source: :hue,
        source_id: "12",
        bridge_id: bridge.id,
        room_id: room.id
      })

    group =
      Repo.insert!(%Group{
        name: "All",
        source: :hue,
        source_id: "21",
        bridge_id: bridge.id,
        room_id: room.id
      })

    Repo.insert!(%GroupLight{group_id: group.id, light_id: light_a.id})
    Repo.insert!(%GroupLight{group_id: group.id, light_id: light_b.id})

    state = %{
      lights_by_id: %{},
      groups_by_id: %{group.source_id => %{id: group.id}},
      group_light_ids: %{},
      group_lights: %{group.id => [light_a.id, light_b.id]}
    }

    Mapper.handle_resource(
      %{
        "type" => "grouped_light",
        "id_v1" => "/groups/#{group.source_id}",
        "on" => %{"on" => true},
        "dimming" => %{"brightness" => 64.0},
        "color_temperature" => %{"mirek" => 400}
      },
      state
    )

    assert State.get(:group, group.id) == %{power: :on, brightness: 64, kelvin: 2500}
    assert State.get(:light, light_a.id) == %{power: :on, brightness: 64, kelvin: 2500}
    assert State.get(:light, light_b.id) == %{power: :on, brightness: 64, kelvin: 2500}
  end

  test "grouped_light event refreshes overlapping child group state from member lights" do
    room = Repo.insert!(%Room{name: "Hue Room"})

    bridge =
      insert_bridge!(%{
        type: :hue,
        name: "Hue",
        host: "10.0.0.43",
        credentials: %{"api_key" => "key"},
        enabled: true
      })

    light_a =
      Repo.insert!(%Light{
        name: "A",
        source: :hue,
        source_id: "11",
        bridge_id: bridge.id,
        room_id: room.id
      })

    light_b =
      Repo.insert!(%Light{
        name: "B",
        source: :hue,
        source_id: "12",
        bridge_id: bridge.id,
        room_id: room.id
      })

    parent =
      Repo.insert!(%Group{
        name: "Main Floor Hue",
        source: :hue,
        source_id: "21",
        bridge_id: bridge.id,
        room_id: room.id
      })

    child =
      Repo.insert!(%Group{
        name: "Living room Lamps",
        source: :hue,
        source_id: "22",
        bridge_id: bridge.id,
        room_id: room.id
      })

    Repo.insert!(%GroupLight{group_id: parent.id, light_id: light_a.id})
    Repo.insert!(%GroupLight{group_id: parent.id, light_id: light_b.id})
    Repo.insert!(%GroupLight{group_id: child.id, light_id: light_a.id})

    _ = State.put(:group, child.id, %{power: :on, brightness: 97, kelvin: 2793})

    state = %{
      lights_by_id: %{},
      groups_by_id: %{parent.source_id => %{id: parent.id}, child.source_id => %{id: child.id}},
      group_light_ids: %{
        light_a.id => [parent.id, child.id],
        light_b.id => [parent.id]
      },
      group_lights: %{
        parent.id => [light_a.id, light_b.id],
        child.id => [light_a.id]
      }
    }

    Mapper.handle_resource(
      %{
        "type" => "grouped_light",
        "id_v1" => "/groups/#{parent.source_id}",
        "on" => %{"on" => true},
        "dimming" => %{"brightness" => 85.0},
        "color_temperature" => %{"mirek" => 485}
      },
      state
    )

    assert State.get(:light, light_a.id) == %{power: :on, brightness: 85, kelvin: 2062}
    assert State.get(:light, light_b.id) == %{power: :on, brightness: 85, kelvin: 2062}
    assert State.get(:group, child.id) == %{power: :on, brightness: 85, kelvin: 2062}
  end

  test "grouped_light owner fallback resolves group id and fans out to members" do
    room = Repo.insert!(%Room{name: "Hue Room"})

    bridge =
      insert_bridge!(%{
        type: :hue,
        name: "Hue",
        host: "10.0.0.41",
        credentials: %{"api_key" => "key"},
        enabled: true
      })

    light =
      Repo.insert!(%Light{
        name: "A",
        source: :hue,
        source_id: "11",
        bridge_id: bridge.id,
        room_id: room.id
      })

    group =
      Repo.insert!(%Group{
        name: "All",
        source: :hue,
        source_id: "21",
        bridge_id: bridge.id,
        room_id: room.id
      })

    Repo.insert!(%GroupLight{group_id: group.id, light_id: light.id})

    state = %{
      lights_by_id: %{},
      groups_by_id: %{group.source_id => %{id: group.id}},
      group_light_ids: %{},
      group_lights: %{group.id => [light.id]}
    }

    Mapper.handle_resource(
      %{
        "type" => "grouped_light",
        "owner" => %{"id_v1" => "/groups/#{group.source_id}"},
        "on" => %{"on" => false}
      },
      state
    )

    assert State.get(:group, group.id) == %{power: :off}
    assert State.get(:light, light.id) == %{power: :off}
  end

  test "light event updates group kelvin average when member kelvins stay within tolerance" do
    room = Repo.insert!(%Room{name: "Hue Room"})

    bridge =
      insert_bridge!(%{
        type: :hue,
        name: "Hue",
        host: "10.0.0.42",
        credentials: %{"api_key" => "key"},
        enabled: true
      })

    light_a =
      Repo.insert!(%Light{
        name: "A",
        source: :hue,
        source_id: "11",
        bridge_id: bridge.id,
        room_id: room.id
      })

    light_b =
      Repo.insert!(%Light{
        name: "B",
        source: :hue,
        source_id: "12",
        bridge_id: bridge.id,
        room_id: room.id
      })

    group =
      Repo.insert!(%Group{
        name: "All",
        source: :hue,
        source_id: "21",
        bridge_id: bridge.id,
        room_id: room.id
      })

    Repo.insert!(%GroupLight{group_id: group.id, light_id: light_a.id})
    Repo.insert!(%GroupLight{group_id: group.id, light_id: light_b.id})

    _ = State.put(:light, light_b.id, %{power: :on, kelvin: 2500})

    state = %{
      lights_by_id: %{
        light_a.source_id => %{id: light_a.id},
        light_b.source_id => %{id: light_b.id}
      },
      groups_by_id: %{group.source_id => %{id: group.id}},
      group_light_ids: %{light_a.id => [group.id], light_b.id => [group.id]},
      group_lights: %{group.id => [light_a.id, light_b.id]}
    }

    Mapper.handle_resource(
      %{
        "type" => "light",
        "id_v1" => "/lights/#{light_a.source_id}",
        "on" => %{"on" => true},
        "color_temperature" => %{"mirek" => 400}
      },
      state
    )

    assert State.get(:light, light_a.id) == %{power: :on, kelvin: 2500}
    assert State.get(:group, group.id) == %{power: :on, kelvin: 2500}
  end

  test "needs_refresh detects unknown light and group resources" do
    state = %{
      lights_by_id: %{"11" => %{id: 1}},
      groups_by_id: %{"21" => %{id: 2}},
      group_light_ids: %{},
      group_lights: %{}
    }

    assert Mapper.needs_refresh?(
             [
               %{"type" => "light", "id_v1" => "/lights/99"}
             ],
             state
           )

    assert Mapper.needs_refresh?(
             [
               %{"type" => "grouped_light", "id_v1" => "/groups/77"}
             ],
             state
           )

    refute Mapper.needs_refresh?(
             [
               %{"type" => "light", "id_v1" => "/lights/11"},
               %{"type" => "grouped_light", "id_v1" => "/groups/21"}
             ],
             state
           )
  end
end
