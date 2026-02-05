defmodule Hueworks.SceneActivationRoundTripTest do
  use HueworksWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Hueworks.Control.Executor
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
        {Executor,
         name: server,
         dispatch_fun: dispatch_fun,
         bridge_rate_fun: fn _ -> 10 end}
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
        room_id: room.id
      })

    light_2 =
      Repo.insert!(%Light{
        name: "Ceiling",
        display_name: "Ceiling",
        source: :hue,
        source_id: "2",
        bridge_id: bridge.id,
        room_id: room.id
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
               desired: %{power: :on, brightness: "50", kelvin: "3000"}
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
        room_id: room.id
      })

    light_b =
      Repo.insert!(%Light{
        name: "B",
        display_name: "B",
        source: :hue,
        source_id: "102",
        bridge_id: bridge.id,
        room_id: room.id
      })

    light_c =
      Repo.insert!(%Light{
        name: "C",
        display_name: "C",
        source: :hue,
        source_id: "103",
        bridge_id: bridge.id,
        room_id: room.id
      })

    light_d =
      Repo.insert!(%Light{
        name: "D",
        display_name: "D",
        source: :hue,
        source_id: "104",
        bridge_id: bridge.id,
        room_id: room.id
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

    Repo.insert!(%SceneComponentLight{scene_component_id: component_warm.id, light_id: light_a.id})
    Repo.insert!(%SceneComponentLight{scene_component_id: component_warm.id, light_id: light_b.id})

    component_cool =
      Repo.insert!(%SceneComponent{
        name: "Cool Component",
        scene_id: scene.id,
        light_state_id: cool_state.id,
        metadata: %{}
      })

    Repo.insert!(%SceneComponentLight{scene_component_id: component_cool.id, light_id: light_c.id})
    Repo.insert!(%SceneComponentLight{scene_component_id: component_cool.id, light_id: light_d.id})

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
               action.desired == %{power: :on, brightness: "40", kelvin: "2400"}
           end)

    assert Enum.any?(actions, fn action ->
             action.type == :group and action.id == group_cd.id and
               action.desired == %{power: :on, brightness: "80", kelvin: "5000"}
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
