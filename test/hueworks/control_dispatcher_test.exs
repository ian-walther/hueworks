defmodule Hueworks.Control.DispatcherTest do
  use Hueworks.DataCase, async: false

  alias Hueworks.Control.{DesiredState, Dispatcher}
  alias Hueworks.Repo
  alias Hueworks.Schemas.{Bridge, Group, GroupLight, Light, Room}

  setup do
    if :ets.whereis(:hueworks_desired_state) != :undefined do
      :ets.delete_all_objects(:hueworks_desired_state)
    end

    :ok
  end

  test "plan_room prefers largest exact-match group and ignores in-state lights for individual actions" do
    room = Repo.insert!(%Room{name: "Studio"})
    bridge =
      Repo.insert!(%Bridge{
        name: "Hue",
        type: :hue,
        host: "bridge-1",
        credentials: %{}
      })

    light_a = insert_light(room, bridge, "A")
    light_b = insert_light(room, bridge, "B")
    light_c = insert_light(room, bridge, "C")

    group_big = insert_group(room, bridge, "All")
    group_small = insert_group(room, bridge, "Pair")

    insert_group_light(group_big, light_a)
    insert_group_light(group_big, light_b)
    insert_group_light(group_big, light_c)
    insert_group_light(group_small, light_a)
    insert_group_light(group_small, light_b)

    desired = %{power: :on, brightness: 50, kelvin: 3000}
    DesiredState.put(:light, light_a.id, desired)
    DesiredState.put(:light, light_b.id, desired)
    DesiredState.put(:light, light_c.id, desired)

    diff = %{
      {:light, light_a.id} => %{power: :on, brightness: 50, kelvin: 3000},
      {:light, light_b.id} => %{power: :on, brightness: 50, kelvin: 3000}
    }

    actions = Dispatcher.plan_room(room.id, diff)

    assert [
             %{type: :group, id: group_id, desired: ^desired}
           ] = actions

    assert group_id == group_big.id
  end

  test "plan_room falls back to individual lights when no exact-match group exists" do
    room = Repo.insert!(%Room{name: "Office"})
    bridge =
      Repo.insert!(%Bridge{
        name: "Hue",
        type: :hue,
        host: "bridge-2",
        credentials: %{}
      })

    light_a = insert_light(room, bridge, "A")
    light_b = insert_light(room, bridge, "B")
    light_c = insert_light(room, bridge, "C")

    group_big = insert_group(room, bridge, "All")

    insert_group_light(group_big, light_a)
    insert_group_light(group_big, light_b)
    insert_group_light(group_big, light_c)

    desired = %{power: :on, brightness: 80, kelvin: 3200}
    DesiredState.put(:light, light_a.id, desired)
    DesiredState.put(:light, light_b.id, desired)
    DesiredState.put(:light, light_c.id, %{power: :off})

    diff = %{
      {:light, light_a.id} => %{power: :on, brightness: 80, kelvin: 3200},
      {:light, light_b.id} => %{power: :on, brightness: 80, kelvin: 3200}
    }

    actions = Dispatcher.plan_room(room.id, diff)

    assert Enum.all?(actions, &(&1.type == :light))
    assert Enum.map(actions, & &1.id) |> Enum.sort() == [light_a.id, light_b.id]
  end

  test "plan_room ignores groups on other bridges" do
    room = Repo.insert!(%Room{name: "Den"})
    bridge =
      Repo.insert!(%Bridge{
        name: "Hue",
        type: :hue,
        host: "bridge-3",
        credentials: %{}
      })

    other_bridge =
      Repo.insert!(%Bridge{
        name: "HA",
        type: :ha,
        host: "bridge-4",
        credentials: %{}
      })

    light_a = insert_light(room, bridge, "A")
    light_b = insert_light(room, bridge, "B")

    group_other = insert_group(room, other_bridge, "Other")
    insert_group_light(group_other, light_a)
    insert_group_light(group_other, light_b)

    desired = %{power: :on, brightness: 40, kelvin: 2700}
    DesiredState.put(:light, light_a.id, desired)
    DesiredState.put(:light, light_b.id, desired)

    diff = %{
      {:light, light_a.id} => %{power: :on, brightness: 40, kelvin: 2700},
      {:light, light_b.id} => %{power: :on, brightness: 40, kelvin: 2700}
    }

    actions = Dispatcher.plan_room(room.id, diff)

    assert Enum.all?(actions, &(&1.type == :light))
    assert Enum.map(actions, & &1.id) |> Enum.sort() == [light_a.id, light_b.id]
  end

  defp insert_light(room, bridge, name) do
    Repo.insert!(%Light{
      name: name,
      display_name: name,
      source: :hue,
      source_id: "light-#{name}-#{System.unique_integer([:positive])}",
      bridge_id: bridge.id,
      room_id: room.id
    })
  end

  defp insert_group(room, bridge, name) do
    Repo.insert!(%Group{
      name: name,
      display_name: name,
      source: :hue,
      source_id: "group-#{name}-#{System.unique_integer([:positive])}",
      bridge_id: bridge.id,
      room_id: room.id
    })
  end

  defp insert_group_light(group, light) do
    Repo.insert!(%GroupLight{group_id: group.id, light_id: light.id})
  end
end
