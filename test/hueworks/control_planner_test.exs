defmodule Hueworks.Control.PlannerTest do
  use Hueworks.DataCase, async: false
  import Ecto.Query, only: [from: 2]

  alias Hueworks.Control.{DesiredState, Planner, State}
  alias Hueworks.Repo
  alias Hueworks.Schemas.{AppSetting, Bridge, Group, GroupLight, Light, Room}

  setup do
    Repo.delete_all(AppSetting)

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

    actions = Planner.plan_room(room.id, diff)

    assert [
             %{type: :group, id: group_id, desired: ^desired}
           ] = actions

    assert group_id == group_big.id
  end

  test "plan_snapshot plans from a preloaded room snapshot without repo lookups" do
    desired = %{power: :on, brightness: 50, kelvin: 3000}

    snapshot = %{
      room_id: 123,
      room_lights: [
        %{
          id: 1,
          bridge_id: 10,
          supports_temp: true,
          reported_min_kelvin: 2000,
          reported_max_kelvin: 6500,
          actual_min_kelvin: nil,
          actual_max_kelvin: nil,
          extended_kelvin_range: false
        },
        %{
          id: 2,
          bridge_id: 10,
          supports_temp: true,
          reported_min_kelvin: 2000,
          reported_max_kelvin: 6500,
          actual_min_kelvin: nil,
          actual_max_kelvin: nil,
          extended_kelvin_range: false
        }
      ],
      desired_by_light: %{1 => desired, 2 => desired},
      physical_by_light: %{1 => %{}, 2 => %{}},
      group_memberships: [%{id: 99, bridge_id: 10, lights: MapSet.new([1, 2])}]
    }

    diff = %{
      {:light, 1} => desired,
      {:light, 2} => desired
    }

    assert [
             %{type: :group, id: 99, bridge_id: 10, desired: ^desired}
           ] = Planner.plan_snapshot(snapshot, diff)
  end

  test "plan_direct builds per-light actions from diff without room context" do
    room = Repo.insert!(%Room{name: "Direct"})

    bridge =
      Repo.insert!(%Bridge{
        name: "Hue",
        type: :hue,
        host: "bridge-direct",
        credentials: %{}
      })

    light_a = insert_light(room, bridge, "A")
    light_b = insert_light(room, bridge, "B")

    desired = %{power: :on, brightness: 55}

    diff = %{
      {:light, light_a.id} => desired,
      {"light", light_b.id} => desired,
      {:group, 999} => %{power: :off}
    }

    actions = Planner.plan_direct(diff)

    assert Enum.sort_by(actions, & &1.id) == [
             %{type: :light, id: light_a.id, bridge_id: bridge.id, desired: desired},
             %{type: :light, id: light_b.id, bridge_id: bridge.id, desired: desired}
           ]
  end

  test "plan_room attaches global transition apply_opts to actions" do
    Repo.insert!(%AppSetting{
      scope: "global",
      latitude: 40.7128,
      longitude: -74.0060,
      timezone: "America/New_York",
      default_transition_ms: 800
    })

    room = Repo.insert!(%Room{name: "Transition Room"})

    bridge =
      Repo.insert!(%Bridge{
        name: "Hue",
        type: :hue,
        host: "bridge-transition",
        credentials: %{}
      })

    light = insert_light(room, bridge, "Lamp")
    desired = %{power: :on, brightness: 55}

    DesiredState.put(:light, light.id, desired)

    diff = %{{:light, light.id} => desired}
    [action] = Planner.plan_room(room.id, diff)

    assert action.type == :light
    assert action.id == light.id
    assert action.apply_opts == %{transition_ms: 800}
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

    actions = Planner.plan_room(room.id, diff)

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

    actions = Planner.plan_room(room.id, diff)

    assert Enum.all?(actions, &(&1.type == :light))
    assert Enum.map(actions, & &1.id) |> Enum.sort() == [light_a.id, light_b.id]
  end

  test "plan_room partitions clamped kelvin values and still optimizes with groups" do
    room = Repo.insert!(%Room{name: "Kitchen"})

    bridge =
      Repo.insert!(%Bridge{
        name: "Hue",
        type: :hue,
        host: "bridge-5",
        credentials: %{}
      })

    ceiling_a =
      insert_light(room, bridge, "CeilingA", reported_min_kelvin: 2000, reported_max_kelvin: 6500)

    ceiling_b =
      insert_light(room, bridge, "CeilingB", reported_min_kelvin: 2000, reported_max_kelvin: 6500)

    table_a =
      insert_light(room, bridge, "TableA", reported_min_kelvin: 2200, reported_max_kelvin: 4500)

    table_b =
      insert_light(room, bridge, "TableB", reported_min_kelvin: 2200, reported_max_kelvin: 4500)

    ceiling_group = insert_group(room, bridge, "Ceiling")
    table_group = insert_group(room, bridge, "Table")

    insert_group_light(ceiling_group, ceiling_a)
    insert_group_light(ceiling_group, ceiling_b)
    insert_group_light(table_group, table_a)
    insert_group_light(table_group, table_b)

    desired = %{power: :on, brightness: 65, kelvin: 2000}

    for light <- [ceiling_a, ceiling_b, table_a, table_b] do
      DesiredState.put(:light, light.id, desired)
    end

    diff =
      Enum.into([ceiling_a, ceiling_b, table_a, table_b], %{}, fn light ->
        {{:light, light.id}, desired}
      end)

    actions = Planner.plan_room(room.id, diff)

    assert length(actions) == 2

    table_action =
      Enum.find(actions, fn action ->
        action.type == :group and (action.desired[:kelvin] || action.desired["kelvin"]) == 2200
      end)

    ceiling_action =
      Enum.find(actions, fn action ->
        action.type == :group and (action.desired[:kelvin] || action.desired["kelvin"]) == 2000
      end)

    assert table_action
    assert ceiling_action

    assert MapSet.new([table_action.id, ceiling_action.id]) ==
             MapSet.new([table_group.id, ceiling_group.id])
  end

  test "plan_room treats adjacent mirek kelvin drift as already in state" do
    room = Repo.insert!(%Room{name: "Warm Drift"})

    bridge =
      Repo.insert!(%Bridge{
        name: "Hue",
        type: :hue,
        host: "bridge-warm-drift",
        credentials: %{}
      })

    light = insert_light(room, bridge, "A", supports_temp: true)
    desired = %{power: :on, brightness: 100, kelvin: 3715}
    DesiredState.put(:light, light.id, desired)
    _ = State.put(:light, light.id, %{power: :on, brightness: 100, kelvin: 3704})

    diff = %{{:light, light.id} => desired}

    assert Planner.plan_room(room.id, diff) == []
  end

  test "plan_room removes kelvin from non-temp partitions while preserving temp partitions" do
    room = Repo.insert!(%Room{name: "Mixed"})

    bridge =
      Repo.insert!(%Bridge{
        name: "HA",
        type: :ha,
        host: "bridge-6",
        credentials: %{}
      })

    temp_a =
      insert_light(room, bridge, "TempA",
        supports_temp: true,
        reported_min_kelvin: 2000,
        reported_max_kelvin: 6500
      )

    temp_b =
      insert_light(room, bridge, "TempB",
        supports_temp: true,
        reported_min_kelvin: 2000,
        reported_max_kelvin: 6500
      )

    dim_a = insert_light(room, bridge, "DimA", supports_temp: false)
    dim_b = insert_light(room, bridge, "DimB", supports_temp: false)

    temp_group = insert_group(room, bridge, "TempGroup")
    dim_group = insert_group(room, bridge, "DimGroup")

    insert_group_light(temp_group, temp_a)
    insert_group_light(temp_group, temp_b)
    insert_group_light(dim_group, dim_a)
    insert_group_light(dim_group, dim_b)

    desired = %{power: :on, brightness: 50, kelvin: 2600}

    for light <- [temp_a, temp_b, dim_a, dim_b] do
      DesiredState.put(:light, light.id, desired)
    end

    diff =
      Enum.into([temp_a, temp_b, dim_a, dim_b], %{}, fn light ->
        {{:light, light.id}, desired}
      end)

    actions = Planner.plan_room(room.id, diff)

    assert length(actions) == 2

    temp_action =
      Enum.find(actions, fn action ->
        action.type == :group and (action.desired[:kelvin] || action.desired["kelvin"]) == 2600
      end)

    dim_action =
      Enum.find(actions, fn action ->
        action.type == :group and
          not Map.has_key?(action.desired, :kelvin) and not Map.has_key?(action.desired, "kelvin") and
          not Map.has_key?(action.desired, :temperature) and
          not Map.has_key?(action.desired, "temperature")
      end)

    assert temp_action
    assert dim_action

    assert MapSet.new([temp_action.id, dim_action.id]) ==
             MapSet.new([temp_group.id, dim_group.id])
  end

  test "plan_room clamps and partitions using full main-floor export topology" do
    {room, _bridge, lights_by_source, groups_by_source} = insert_main_floor_fixture()

    desired = %{power: :on, brightness: 55, kelvin: 2000}

    for {_source_id, light} <- lights_by_source do
      DesiredState.put(:light, light.id, desired)
    end

    diff =
      Enum.into(lights_by_source, %{}, fn {_source_id, light} ->
        {{:light, light.id}, desired}
      end)

    actions = Planner.plan_room(room.id, diff)

    assert length(actions) < map_size(lights_by_source)
    assert Enum.any?(actions, &(&1.type == :group))

    assert Enum.any?(actions, fn action ->
             (action.desired[:kelvin] || action.desired["kelvin"]) == 2202
           end)

    assert Enum.any?(actions, fn action ->
             (action.desired[:kelvin] || action.desired["kelvin"]) == 2000
           end)

    group_lights =
      groups_by_source
      |> Enum.map(fn {_source_id, group} -> {group.id, load_group_light_ids(group.id)} end)
      |> Map.new()

    expected_kelvin_by_light =
      Map.new(lights_by_source, fn {_source_id, light} ->
        clamped =
          min(max(2000, light.reported_min_kelvin || 2000), light.reported_max_kelvin || 6535)

        {light.id, clamped}
      end)

    actual_kelvin_by_light =
      Enum.reduce(actions, %{}, fn action, acc ->
        kelvin = action.desired[:kelvin] || action.desired["kelvin"]

        cond do
          is_nil(kelvin) ->
            acc

          action.type == :light ->
            Map.update(acc, action.id, MapSet.new([kelvin]), &MapSet.put(&1, kelvin))

          action.type == :group ->
            member_ids = Map.get(group_lights, action.id, MapSet.new())

            Enum.reduce(member_ids, acc, fn light_id, inner ->
              Map.update(inner, light_id, MapSet.new([kelvin]), &MapSet.put(&1, kelvin))
            end)

          true ->
            acc
        end
      end)

    Enum.each(expected_kelvin_by_light, fn {light_id, expected_kelvin} ->
      values = Map.get(actual_kelvin_by_light, light_id, MapSet.new())
      assert values != MapSet.new()
      assert values == MapSet.new([expected_kelvin])
    end)
  end

  test "plan_room uses one group for uniform manual scene but five groups for clamped circadian scene on same main-floor lights" do
    {room, _bridge, lights_by_source, groups_by_source} = insert_main_floor_fixture()

    uniform_desired = %{power: :on, brightness: 100, kelvin: 3501}

    for {_source_id, light} <- lights_by_source do
      DesiredState.put(:light, light.id, uniform_desired)
    end

    uniform_diff =
      Enum.into(lights_by_source, %{}, fn {_source_id, light} ->
        {{:light, light.id}, uniform_desired}
      end)

    uniform_actions = Planner.plan_room(room.id, uniform_diff)

    assert [
             %{
               type: :group,
               id: main_floor_group_id,
               desired: ^uniform_desired
             }
           ] = uniform_actions

    assert groups_by_source["light.main_floor"].id == main_floor_group_id

    clamped_desired = %{power: :on, brightness: 77, kelvin: 2000}

    for {_source_id, light} <- lights_by_source do
      DesiredState.put(:light, light.id, clamped_desired)
    end

    clamped_diff =
      Enum.into(lights_by_source, %{}, fn {_source_id, light} ->
        {{:light, light.id}, clamped_desired}
      end)

    clamped_actions = Planner.plan_room(room.id, clamped_diff)

    assert length(clamped_actions) == 5
    assert Enum.all?(clamped_actions, &(&1.type == :group))

    action_source_ids =
      clamped_actions
      |> Enum.map(fn action ->
        Enum.find_value(groups_by_source, fn {source_id, group} ->
          if group.id == action.id, do: source_id
        end)
      end)
      |> MapSet.new()

    assert action_source_ids ==
             MapSet.new([
               "light.main_floor_ceiling",
               "light.living_room",
               "light.kitchen_ceiling",
               "light.ians_office",
               "light.kitchen_hanging"
             ])

    kelvins =
      clamped_actions
      |> Enum.map(fn action -> action.desired[:kelvin] || action.desired["kelvin"] end)
      |> Enum.sort()

    assert kelvins == [2000, 2000, 2000, 2000, 2202]
  end

  test "plan_room skips actions when effective desired already matches physical state" do
    room = Repo.insert!(%Room{name: "Clamp Match"})

    bridge =
      Repo.insert!(%Bridge{
        name: "Hue",
        type: :hue,
        host: "bridge-clamp-match",
        credentials: %{}
      })

    light_a =
      insert_light(room, bridge, "A", reported_min_kelvin: 2200, reported_max_kelvin: 4500)

    light_b =
      insert_light(room, bridge, "B", reported_min_kelvin: 2200, reported_max_kelvin: 4500)

    desired = %{power: :on, brightness: 65, kelvin: 2000}

    DesiredState.put(:light, light_a.id, desired)
    DesiredState.put(:light, light_b.id, desired)

    if :ets.whereis(:hueworks_control_state) != :undefined do
      :ets.insert(
        :hueworks_control_state,
        {{:light, light_a.id}, %{power: :on, brightness: 65, kelvin: 2200}}
      )

      :ets.insert(
        :hueworks_control_state,
        {{:light, light_b.id}, %{power: :on, brightness: 65, kelvin: 2200}}
      )
    end

    diff = %{
      {:light, light_a.id} => desired,
      {:light, light_b.id} => desired
    }

    assert Planner.plan_room(room.id, diff) == []
  end

  defp insert_light(room, bridge, name, opts \\ []) do
    Repo.insert!(%Light{
      name: name,
      display_name: name,
      source: :hue,
      source_id: "light-#{name}-#{System.unique_integer([:positive])}",
      bridge_id: bridge.id,
      room_id: room.id,
      supports_temp: Keyword.get(opts, :supports_temp, true),
      reported_min_kelvin: Keyword.get(opts, :reported_min_kelvin, 2000),
      reported_max_kelvin: Keyword.get(opts, :reported_max_kelvin, 6500)
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

  defp load_group_light_ids(group_id) do
    Repo.all(
      from(gl in GroupLight,
        where: gl.group_id == ^group_id,
        select: gl.light_id
      )
    )
    |> MapSet.new()
  end

  defp load_main_floor_fixture do
    "test/fixtures/planner/main_floor_export.json"
    |> File.read!()
    |> Jason.decode!()
  end

  defp insert_main_floor_fixture do
    fixture = load_main_floor_fixture()

    room = Repo.insert!(%Room{name: "Main Floor Fixture"})

    bridge =
      Repo.insert!(%Bridge{
        name: "HA",
        type: :ha,
        host: "bridge-main-floor-#{System.unique_integer([:positive])}",
        credentials: %{}
      })

    light_ranges = ranges_for_main_floor_lights(fixture)

    lights_by_source =
      fixture["lights"]
      |> Enum.reduce(%{}, fn light_data, acc ->
        source_id = light_data["source_id"]
        {min_kelvin, max_kelvin} = Map.get(light_ranges, source_id, {2000, 6535})
        name = light_data["name"] || source_id

        light =
          Repo.insert!(%Light{
            name: name,
            display_name: name,
            source: :ha,
            source_id: source_id,
            bridge_id: bridge.id,
            room_id: room.id,
            supports_temp: true,
            reported_min_kelvin: min_kelvin,
            reported_max_kelvin: max_kelvin
          })

        Map.put(acc, source_id, light)
      end)

    groups_by_source =
      fixture["groups"]
      |> Enum.reduce(%{}, fn group_data, acc ->
        source_id = group_data["source_id"]
        name = group_data["name"] || source_id

        group =
          Repo.insert!(%Group{
            name: name,
            display_name: name,
            source: :ha,
            source_id: source_id,
            bridge_id: bridge.id,
            room_id: room.id
          })

        Enum.each(group_data["members"] || [], fn light_source_id ->
          case Map.get(lights_by_source, light_source_id) do
            nil -> :ok
            light -> insert_group_light(group, light)
          end
        end)

        Map.put(acc, source_id, group)
      end)

    {room, bridge, lights_by_source, groups_by_source}
  end

  defp ranges_for_main_floor_lights(fixture) do
    light_ids =
      fixture["lights"]
      |> Enum.map(& &1["source_id"])
      |> Enum.filter(&is_binary/1)

    filament_ids =
      light_ids
      |> Enum.filter(&String.contains?(&1, "filament_bulb"))
      |> MapSet.new()

    Enum.reduce(light_ids, %{}, fn light_id, acc ->
      range =
        if MapSet.member?(filament_ids, light_id) do
          {2202, 4504}
        else
          {2000, 6535}
        end

      Map.put(acc, light_id, range)
    end)
  end
end
