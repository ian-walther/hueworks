defmodule Hueworks.SceneActivationRoundTripTest do
  use HueworksWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Hueworks.ActiveScenes
  alias Hueworks.Control.DesiredState
  alias Hueworks.Control.Executor
  alias Hueworks.Control.State
  alias Hueworks.Repo

  alias Hueworks.Schemas.{
    Bridge,
    Group,
    GroupLight,
    Light,
    LightState,
    Room,
    Scene,
    SceneComponent,
    SceneComponentLight
  }

  setup do
    actions_id = {:executor_roundtrip_actions, self()}
    {:ok, actions_agent} = start_supervised({Agent, fn -> [] end}, id: actions_id)

    dispatch_fun = fn action ->
      Agent.update(actions_agent, fn actions -> actions ++ [action] end)
      :ok
    end

    server = {:global, {:executor_roundtrip, self()}}

    {:ok, _pid} =
      start_supervised(
        {Executor, name: server, dispatch_fun: dispatch_fun, bridge_rate_fun: fn _ -> 10 end}
      )

    original_enabled = Application.get_env(:hueworks, :control_executor_enabled)
    original_server = Application.get_env(:hueworks, :control_executor_server)

    Application.put_env(:hueworks, :control_executor_enabled, true)
    Application.put_env(:hueworks, :control_executor_server, server)

    on_exit(fn ->
      Application.put_env(:hueworks, :control_executor_enabled, original_enabled)
      Application.put_env(:hueworks, :control_executor_server, original_server)
    end)

    {:ok, actions_agent: actions_agent, executor_server: server}
  end

  test "clicking activate in the DOM enqueues and dispatches a hardware action", %{
    conn: conn,
    actions_agent: actions_agent,
    executor_server: executor_server
  } do
    room = Repo.insert!(%Room{name: "Studio"})

    bridge =
      Repo.insert!(%Bridge{
        name: "Hue Bridge",
        type: :hue,
        host: "192.168.1.2",
        credentials: %{"api_key" => "test"}
      })

    light_1 =
      Repo.insert!(%Light{
        name: "Lamp",
        display_name: "Lamp",
        source: :hue,
        source_id: "1",
        bridge_id: bridge.id,
        room_id: room.id,
        supports_temp: true,
        reported_min_kelvin: 2000,
        reported_max_kelvin: 6500
      })

    light_2 =
      Repo.insert!(%Light{
        name: "Ceiling",
        display_name: "Ceiling",
        source: :hue,
        source_id: "2",
        bridge_id: bridge.id,
        room_id: room.id,
        supports_temp: true,
        reported_min_kelvin: 2000,
        reported_max_kelvin: 6500
      })

    group =
      Repo.insert!(%Group{
        name: "Room Group",
        display_name: "Room Group",
        source: :hue,
        source_id: "10",
        bridge_id: bridge.id,
        room_id: room.id
      })

    Repo.insert!(%GroupLight{group_id: group.id, light_id: light_1.id})
    Repo.insert!(%GroupLight{group_id: group.id, light_id: light_2.id})

    light_state =
      Repo.insert!(%LightState{
        name: "Bright",
        type: :manual,
        config: %{"brightness" => "50", "temperature" => "3000"}
      })

    scene =
      Repo.insert!(%Scene{
        name: "Chill",
        room_id: room.id,
        metadata: %{}
      })

    component =
      Repo.insert!(%SceneComponent{
        name: "Component 1",
        scene_id: scene.id,
        light_state_id: light_state.id,
        metadata: %{}
      })

    Repo.insert!(%SceneComponentLight{scene_component_id: component.id, light_id: light_1.id})
    Repo.insert!(%SceneComponentLight{scene_component_id: component.id, light_id: light_2.id})

    reset_states_for_lights([light_1.id, light_2.id])

    {:ok, view, _html} = live(conn, "/rooms")

    view
    |> element("button[phx-click=\"activate_scene\"][phx-value-id=\"#{scene.id}\"]")
    |> render_click()

    drain_executor(executor_server)

    actions = Agent.get(actions_agent, & &1)
    group_id = group.id

    assert [
             %{
               type: :group,
               id: ^group_id,
               desired: %{power: :on, brightness: 50, kelvin: 3000}
             }
           ] = actions
  end

  test "multiple components dispatch group and individual actions with correct targets", %{
    conn: conn,
    actions_agent: actions_agent,
    executor_server: executor_server
  } do
    room = Repo.insert!(%Room{name: "Loft"})

    bridge =
      Repo.insert!(%Bridge{
        name: "Hue Bridge",
        type: :hue,
        host: "192.168.1.3",
        credentials: %{"api_key" => "test"}
      })

    light_a =
      Repo.insert!(%Light{
        name: "A",
        display_name: "A",
        source: :hue,
        source_id: "101",
        bridge_id: bridge.id,
        room_id: room.id,
        supports_temp: true,
        reported_min_kelvin: 2000,
        reported_max_kelvin: 6500
      })

    light_b =
      Repo.insert!(%Light{
        name: "B",
        display_name: "B",
        source: :hue,
        source_id: "102",
        bridge_id: bridge.id,
        room_id: room.id,
        supports_temp: true,
        reported_min_kelvin: 2000,
        reported_max_kelvin: 6500
      })

    light_c =
      Repo.insert!(%Light{
        name: "C",
        display_name: "C",
        source: :hue,
        source_id: "103",
        bridge_id: bridge.id,
        room_id: room.id,
        supports_temp: true,
        reported_min_kelvin: 2000,
        reported_max_kelvin: 6500
      })

    light_d =
      Repo.insert!(%Light{
        name: "D",
        display_name: "D",
        source: :hue,
        source_id: "104",
        bridge_id: bridge.id,
        room_id: room.id,
        supports_temp: true,
        reported_min_kelvin: 2000,
        reported_max_kelvin: 6500
      })

    group_ab =
      Repo.insert!(%Group{
        name: "AB Group",
        display_name: "AB Group",
        source: :hue,
        source_id: "201",
        bridge_id: bridge.id,
        room_id: room.id
      })

    group_cd =
      Repo.insert!(%Group{
        name: "CD Group",
        display_name: "CD Group",
        source: :hue,
        source_id: "202",
        bridge_id: bridge.id,
        room_id: room.id
      })

    Repo.insert!(%GroupLight{group_id: group_ab.id, light_id: light_a.id})
    Repo.insert!(%GroupLight{group_id: group_ab.id, light_id: light_b.id})
    Repo.insert!(%GroupLight{group_id: group_cd.id, light_id: light_c.id})
    Repo.insert!(%GroupLight{group_id: group_cd.id, light_id: light_d.id})

    warm_state =
      Repo.insert!(%LightState{
        name: "Warm",
        type: :manual,
        config: %{"brightness" => "40", "temperature" => "2400"}
      })

    cool_state =
      Repo.insert!(%LightState{
        name: "Cool",
        type: :manual,
        config: %{"brightness" => "80", "temperature" => "5000"}
      })

    scene =
      Repo.insert!(%Scene{
        name: "Mix",
        room_id: room.id,
        metadata: %{}
      })

    component_warm =
      Repo.insert!(%SceneComponent{
        name: "Warm Component",
        scene_id: scene.id,
        light_state_id: warm_state.id,
        metadata: %{}
      })

    Repo.insert!(%SceneComponentLight{
      scene_component_id: component_warm.id,
      light_id: light_a.id
    })

    Repo.insert!(%SceneComponentLight{
      scene_component_id: component_warm.id,
      light_id: light_b.id
    })

    component_cool =
      Repo.insert!(%SceneComponent{
        name: "Cool Component",
        scene_id: scene.id,
        light_state_id: cool_state.id,
        metadata: %{}
      })

    Repo.insert!(%SceneComponentLight{
      scene_component_id: component_cool.id,
      light_id: light_c.id
    })

    Repo.insert!(%SceneComponentLight{
      scene_component_id: component_cool.id,
      light_id: light_d.id
    })

    reset_states_for_lights([light_a.id, light_b.id, light_c.id, light_d.id])

    {:ok, view, _html} = live(conn, "/rooms")

    view
    |> element("button[phx-click=\"activate_scene\"][phx-value-id=\"#{scene.id}\"]")
    |> render_click()

    drain_executor(executor_server)

    actions = Agent.get(actions_agent, & &1)
    action_ids = Enum.map(actions, & &1.id) |> Enum.sort()

    assert action_ids == Enum.sort([group_ab.id, group_cd.id])

    assert Enum.any?(actions, fn action ->
             action.type == :group and action.id == group_ab.id and
               action.desired == %{power: :on, brightness: 40, kelvin: 2400}
           end)

    assert Enum.any?(actions, fn action ->
             action.type == :group and action.id == group_cd.id and
               action.desired == %{power: :on, brightness: 80, kelvin: 5000}
           end)
  end

  test "default-off light in a manual component dispatches an explicit off action", %{
    conn: conn,
    actions_agent: actions_agent,
    executor_server: executor_server
  } do
    room = Repo.insert!(%Room{name: "Kitchen"})

    bridge =
      Repo.insert!(%Bridge{
        name: "Hue Bridge",
        type: :hue,
        host: "192.168.1.9",
        credentials: %{"api_key" => "test"}
      })

    light_on =
      Repo.insert!(%Light{
        name: "Counter",
        display_name: "Counter",
        source: :hue,
        source_id: "301",
        bridge_id: bridge.id,
        room_id: room.id,
        supports_temp: true,
        reported_min_kelvin: 2000,
        reported_max_kelvin: 6500
      })

    light_off =
      Repo.insert!(%Light{
        name: "Accent",
        display_name: "Accent",
        source: :hue,
        source_id: "302",
        bridge_id: bridge.id,
        room_id: room.id,
        supports_temp: true,
        reported_min_kelvin: 2000,
        reported_max_kelvin: 6500
      })

    group =
      Repo.insert!(%Group{
        name: "Kitchen Group",
        display_name: "Kitchen Group",
        source: :hue,
        source_id: "401",
        bridge_id: bridge.id,
        room_id: room.id
      })

    Repo.insert!(%GroupLight{group_id: group.id, light_id: light_on.id})
    Repo.insert!(%GroupLight{group_id: group.id, light_id: light_off.id})

    light_state =
      Repo.insert!(%LightState{
        name: "Warm",
        type: :manual,
        config: %{"brightness" => "45", "temperature" => "2800"}
      })

    scene =
      Repo.insert!(%Scene{
        name: "Evening",
        room_id: room.id,
        metadata: %{}
      })

    component =
      Repo.insert!(%SceneComponent{
        name: "Component 1",
        scene_id: scene.id,
        light_state_id: light_state.id,
        metadata: %{}
      })

    Repo.insert!(%SceneComponentLight{
      scene_component_id: component.id,
      light_id: light_on.id,
      default_power: :force_on
    })

    Repo.insert!(%SceneComponentLight{
      scene_component_id: component.id,
      light_id: light_off.id,
      default_power: :force_off
    })

    if :ets.whereis(:hueworks_control_state) != :undefined do
      :ets.insert(:hueworks_control_state, {{:light, light_on.id}, %{power: :off}})

      :ets.insert(
        :hueworks_control_state,
        {{:light, light_off.id}, %{power: :on, brightness: 30}}
      )
    end

    if :ets.whereis(:hueworks_desired_state) != :undefined do
      :ets.delete(:hueworks_desired_state, {:light, light_on.id})
      :ets.delete(:hueworks_desired_state, {:light, light_off.id})
    end

    {:ok, view, _html} = live(conn, "/rooms")

    view
    |> element("button[phx-click=\"activate_scene\"][phx-value-id=\"#{scene.id}\"]")
    |> render_click()

    drain_executor(executor_server)

    actions = Agent.get(actions_agent, & &1)

    assert Enum.any?(actions, fn action ->
             action.type == :light and action.id == light_on.id and
               action.desired[:power] == :on and action.desired[:brightness] == 45 and
               action.desired[:kelvin] == 2800
           end)

    assert Enum.any?(actions, fn action ->
             action.type == :light and action.id == light_off.id and
               action.desired[:power] == :off
           end)
  end

  test "scene activation still dispatches off for default-off lights when state tables already say off",
       %{
         conn: conn,
         actions_agent: actions_agent,
         executor_server: executor_server
       } do
    room = Repo.insert!(%Room{name: "Hallway"})

    bridge =
      Repo.insert!(%Bridge{
        name: "Hue Bridge",
        type: :hue,
        host: "192.168.1.10",
        credentials: %{"api_key" => "test"}
      })

    light =
      Repo.insert!(%Light{
        name: "Niche",
        display_name: "Niche",
        source: :hue,
        source_id: "501",
        bridge_id: bridge.id,
        room_id: room.id,
        supports_temp: true,
        reported_min_kelvin: 2000,
        reported_max_kelvin: 6500
      })

    light_state =
      Repo.insert!(%LightState{
        name: "Warm",
        type: :manual,
        config: %{"brightness" => "45", "temperature" => "2800"}
      })

    scene =
      Repo.insert!(%Scene{
        name: "Night",
        room_id: room.id,
        metadata: %{}
      })

    component =
      Repo.insert!(%SceneComponent{
        name: "Component 1",
        scene_id: scene.id,
        light_state_id: light_state.id,
        metadata: %{}
      })

    Repo.insert!(%SceneComponentLight{
      scene_component_id: component.id,
      light_id: light.id,
      default_power: :force_off
    })

    if :ets.whereis(:hueworks_control_state) != :undefined do
      :ets.insert(:hueworks_control_state, {{:light, light.id}, %{power: :off}})
    end

    if :ets.whereis(:hueworks_desired_state) != :undefined do
      :ets.insert(:hueworks_desired_state, {{:light, light.id}, %{power: :off}})
    end

    {:ok, view, _html} = live(conn, "/rooms")

    view
    |> element("button[phx-click=\"activate_scene\"][phx-value-id=\"#{scene.id}\"]")
    |> render_click()

    drain_executor(executor_server)

    actions = Agent.get(actions_agent, & &1)

    assert Enum.any?(actions, fn action ->
             action.type == :light and action.id == light.id and action.desired[:power] == :off
           end)
  end

  test "occupancy toggle dispatches follow_occupancy power changes and also catches stale force_on lights",
       %{
         conn: conn,
         actions_agent: actions_agent,
         executor_server: executor_server
       } do
    room = Repo.insert!(%Room{name: "Occupancy Test"})

    bridge =
      Repo.insert!(%Bridge{
        name: "Hue Bridge",
        type: :hue,
        host: "192.168.1.11",
        credentials: %{"api_key" => "test"}
      })

    force_on_light =
      Repo.insert!(%Light{
        name: "Always On",
        display_name: "Always On",
        source: :hue,
        source_id: "601",
        bridge_id: bridge.id,
        room_id: room.id,
        supports_temp: true,
        reported_min_kelvin: 2000,
        reported_max_kelvin: 6500
      })

    follow_light =
      Repo.insert!(%Light{
        name: "Follow",
        display_name: "Follow",
        source: :hue,
        source_id: "602",
        bridge_id: bridge.id,
        room_id: room.id,
        supports_temp: true,
        reported_min_kelvin: 2000,
        reported_max_kelvin: 6500
      })

    light_state =
      Repo.insert!(%LightState{
        name: "Warm",
        type: :manual,
        config: %{"brightness" => "45", "temperature" => "2800"}
      })

    scene =
      Repo.insert!(%Scene{
        name: "Night",
        room_id: room.id,
        metadata: %{}
      })

    component =
      Repo.insert!(%SceneComponent{
        name: "Component 1",
        scene_id: scene.id,
        light_state_id: light_state.id,
        metadata: %{}
      })

    Repo.insert!(%SceneComponentLight{
      scene_component_id: component.id,
      light_id: force_on_light.id,
      default_power: :force_on
    })

    Repo.insert!(%SceneComponentLight{
      scene_component_id: component.id,
      light_id: follow_light.id,
      default_power: :follow_occupancy
    })

    {:ok, _} = ActiveScenes.set_active(scene)

    _ =
      DesiredState.put(:light, force_on_light.id, %{power: :on, brightness: "45", kelvin: "2800"})

    _ = DesiredState.put(:light, follow_light.id, %{power: :on, brightness: "45", kelvin: "2800"})

    _ = State.put(:light, force_on_light.id, %{power: :on, brightness: 10, kelvin: 4000})
    _ = State.put(:light, follow_light.id, %{power: :on, brightness: 45, kelvin: 2800})

    {:ok, view, _html} = live(conn, "/rooms")

    view
    |> element(
      "#room-#{room.id} button[phx-click='toggle_occupancy'][phx-value-room_id='#{room.id}']"
    )
    |> render_click()

    drain_executor(executor_server)

    actions = Agent.get(actions_agent, & &1)

    assert Enum.any?(actions, fn action ->
             action.type == :light and action.id == follow_light.id and
               action.desired[:power] == :off
           end)

    assert Enum.any?(actions, fn action ->
             action.type == :light and action.id == force_on_light.id and
               action.desired[:power] == :on and action.desired[:brightness] == 45 and
               action.desired[:kelvin] == 2800
           end)
  end

  defp drain_executor(server, attempts \\ 5)

  defp drain_executor(_server, 0), do: :ok

  defp drain_executor(server, attempts) do
    stats = Executor.stats(server)
    queues = Map.values(stats.queues)

    if Enum.all?(queues, &(&1 == 0)) do
      :ok
    else
      Executor.tick(server, force: true)
      drain_executor(server, attempts - 1)
    end
  end

  defp reset_states_for_lights(light_ids) do
    if :ets.whereis(:hueworks_control_state) != :undefined do
      Enum.each(light_ids, fn id ->
        :ets.insert(:hueworks_control_state, {{:light, id}, %{power: :off}})
      end)
    end

    if :ets.whereis(:hueworks_desired_state) != :undefined do
      Enum.each(light_ids, fn id ->
        :ets.delete(:hueworks_desired_state, {:light, id})
      end)
    end
  end
end
