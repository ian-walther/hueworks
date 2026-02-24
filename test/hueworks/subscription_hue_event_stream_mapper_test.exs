defmodule Hueworks.Subscription.HueEventStream.MapperTest do
  use Hueworks.DataCase, async: false

  alias Hueworks.Control.State
  alias Hueworks.Repo
  alias Hueworks.Schemas.{Bridge, Group, GroupLight, Light, Room}
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
      Repo.insert!(%Bridge{
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

  test "grouped_light owner fallback resolves group id and fans out to members" do
    room = Repo.insert!(%Room{name: "Hue Room"})

    bridge =
      Repo.insert!(%Bridge{
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
end
