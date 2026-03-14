defmodule Hueworks.LightsLivePipelineTest do
  use HueworksWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Hueworks.AppSettings
  alias Hueworks.ActiveScenes
  alias Hueworks.Control.{DesiredState, Executor, State}
  alias Hueworks.Scenes
  alias Hueworks.Repo

  alias Hueworks.Schemas.{
    Bridge,
    Group,
    GroupLight,
    Light,
    Room
  }

  setup do
    actions_id = {:executor_lights_pipeline_actions, self()}
    {:ok, actions_agent} = start_supervised({Agent, fn -> [] end}, id: actions_id)

    dispatch_fun = fn action ->
      Agent.update(actions_agent, fn actions -> actions ++ [action] end)
      :ok
    end

    server = {:global, {:executor_lights_pipeline, self()}}

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

  test "manual light toggle enqueues through desired-state pipeline without direct state mutation",
       %{
         conn: conn,
         actions_agent: actions_agent,
         executor_server: executor_server
       } do
    room = Repo.insert!(%Room{name: "Studio"})

    bridge =
      Repo.insert!(%Bridge{
        name: "Hue Bridge",
        type: :hue,
        host: "192.168.1.80",
        credentials: %{"api_key" => "test"}
      })

    light =
      Repo.insert!(%Light{
        name: "Desk Lamp",
        display_name: "Desk Lamp",
        source: :hue,
        source_id: "light-1",
        bridge_id: bridge.id,
        room_id: room.id,
        supports_temp: true,
        reported_min_kelvin: 2000,
        reported_max_kelvin: 6500
      })

    clear_light_states(light.id)

    {:ok, view, _html} = live(conn, "/lights")

    view
    |> element("button[phx-click='toggle'][phx-value-type='light'][phx-value-id='#{light.id}']")
    |> render_click()

    drain_executor(executor_server)

    actions = Agent.get(actions_agent, & &1)

    assert [
             %{
               type: :light,
               id: light_id,
               desired: %{power: :on}
             }
           ] = actions

    assert light_id == light.id
    assert DesiredState.get(:light, light.id) == %{power: :on}

    physical = State.get(:light, light.id)
    assert physical[:power] in [:off, "off", false]
  end

  test "manual group temperature change enqueues planner output and updates desired for member lights",
       %{
         conn: conn,
         actions_agent: actions_agent,
         executor_server: executor_server
       } do
    room = Repo.insert!(%Room{name: "Kitchen"})

    bridge =
      Repo.insert!(%Bridge{
        name: "Hue Bridge",
        type: :hue,
        host: "192.168.1.81",
        credentials: %{"api_key" => "test"}
      })

    light_a =
      Repo.insert!(%Light{
        name: "Kitchen A",
        display_name: "Kitchen A",
        source: :hue,
        source_id: "light-a",
        bridge_id: bridge.id,
        room_id: room.id,
        supports_temp: true,
        reported_min_kelvin: 2000,
        reported_max_kelvin: 6500
      })

    light_b =
      Repo.insert!(%Light{
        name: "Kitchen B",
        display_name: "Kitchen B",
        source: :hue,
        source_id: "light-b",
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
        source_id: "group-kitchen",
        bridge_id: bridge.id,
        room_id: room.id,
        supports_temp: true,
        reported_min_kelvin: 2000,
        reported_max_kelvin: 6500
      })

    Repo.insert!(%GroupLight{group_id: group.id, light_id: light_a.id})
    Repo.insert!(%GroupLight{group_id: group.id, light_id: light_b.id})

    clear_light_states(light_a.id)
    clear_light_states(light_b.id)

    {:ok, view, _html} = live(conn, "/lights")

    _ =
      render_hook(view, "set_color_temp", %{
        "type" => "group",
        "id" => Integer.to_string(group.id),
        "kelvin" => "2400"
      })

    drain_executor(executor_server)

    actions = Agent.get(actions_agent, & &1)

    assert [
             %{
               type: :group,
               id: group_id,
               desired: %{kelvin: 2400}
             }
           ] = actions

    assert group_id == group.id
    assert DesiredState.get(:light, light_a.id) == %{kelvin: 2400}
    assert DesiredState.get(:light, light_b.id) == %{kelvin: 2400}

    physical_group = State.get(:group, group.id)
    assert physical_group[:kelvin] != 2400
  end

  test "manual light toggle can be used repeatedly without reload",
       %{
         conn: conn,
         actions_agent: actions_agent,
         executor_server: executor_server
       } do
    room = Repo.insert!(%Room{name: "Office"})

    bridge =
      Repo.insert!(%Bridge{
        name: "Hue Bridge",
        type: :hue,
        host: "192.168.1.82",
        credentials: %{"api_key" => "test"}
      })

    light =
      Repo.insert!(%Light{
        name: "Office Lamp",
        display_name: "Office Lamp",
        source: :hue,
        source_id: "light-office",
        bridge_id: bridge.id,
        room_id: room.id,
        supports_temp: true,
        reported_min_kelvin: 2000,
        reported_max_kelvin: 6500
      })

    clear_light_states(light.id)

    {:ok, view, _html} = live(conn, "/lights")

    view
    |> element("button[phx-click='toggle'][phx-value-type='light'][phx-value-id='#{light.id}']")
    |> render_click()

    drain_executor(executor_server)

    view
    |> element("button[phx-click='toggle'][phx-value-type='light'][phx-value-id='#{light.id}']")
    |> render_click()

    drain_executor(executor_server)

    actions = Agent.get(actions_agent, & &1)

    assert [
             %{type: :light, id: first_id, desired: %{power: :on}},
             %{type: :light, id: second_id, desired: %{power: :off}}
           ] = actions

    assert first_id == light.id
    assert second_id == light.id
    assert DesiredState.get(:light, light.id) == %{power: :off}
  end

  test "manual power-on while a circadian scene is active immediately reapplies circadian values for only that light",
       %{
         conn: conn,
         actions_agent: actions_agent,
         executor_server: executor_server
       } do
    room = Repo.insert!(%Room{name: "Bedroom"})

    bridge =
      Repo.insert!(%Bridge{
        name: "Hue Bridge",
        type: :hue,
        host: "192.168.1.84",
        credentials: %{"api_key" => "test"}
      })

    light_a =
      Repo.insert!(%Light{
        name: "Bed Left",
        display_name: "Bed Left",
        source: :hue,
        source_id: "bed-left",
        bridge_id: bridge.id,
        room_id: room.id,
        supports_temp: true,
        reported_min_kelvin: 2000,
        reported_max_kelvin: 6500
      })

    light_b =
      Repo.insert!(%Light{
        name: "Bed Right",
        display_name: "Bed Right",
        source: :hue,
        source_id: "bed-right",
        bridge_id: bridge.id,
        room_id: room.id,
        supports_temp: true,
        reported_min_kelvin: 2000,
        reported_max_kelvin: 6500
      })

    {:ok, state} =
      Scenes.create_light_state("Circadian", :circadian, %{
        "sunrise_time" => "06:00:00",
        "sunset_time" => "18:00:00",
        "min_brightness" => 90,
        "max_brightness" => 90,
        "min_color_temp" => 5000,
        "max_color_temp" => 5000
      })

    {:ok, scene} = Scenes.create_scene(%{name: "Circadian", room_id: room.id})

    {:ok, _} =
      Scenes.replace_scene_components(scene, [
        %{
          name: "Circadian Component",
          light_ids: [light_a.id, light_b.id],
          light_state_id: to_string(state.id)
        }
      ])

    {:ok, _} = ActiveScenes.set_active(scene)

    {:ok, _} =
      AppSettings.upsert_global(%{
        latitude: 40.7128,
        longitude: -74.0060,
        timezone: "Etc/UTC"
      })

    _ = ActiveScenes.set_brightness_override(room.id, true)
    _ = DesiredState.put(:light, light_a.id, %{power: :off})
    _ = DesiredState.put(:light, light_b.id, %{power: :off})
    _ = State.put(:light, light_a.id, %{power: :off})
    _ = State.put(:light, light_b.id, %{power: :off})

    {:ok, view, _html} = live(conn, "/lights")

    view
    |> element("button[phx-click='toggle'][phx-value-type='light'][phx-value-id='#{light_a.id}']")
    |> render_click()

    drain_executor(executor_server)

    actions = Agent.get(actions_agent, & &1)

    assert [
             %{type: :light, id: first_id, desired: %{power: :on}},
             %{type: :light, id: second_id, desired: %{power: :on, brightness: 90, kelvin: 5000}}
           ] = actions

    assert first_id == light_a.id
    assert second_id == light_a.id
    assert DesiredState.get(:light, light_a.id) == %{power: :on, brightness: 90, kelvin: 5000}
    assert DesiredState.get(:light, light_b.id) == %{power: :off}
  end

  test "group/light filter prefs persist across page reload", %{conn: conn} do
    session_id = Ecto.UUID.generate()
    conn = Plug.Test.init_test_session(conn, %{"filter_session_id" => session_id})

    {:ok, view, _html} = live(conn, "/lights")
    first_session_id = :sys.get_state(view.pid).socket.assigns.filter_session_id
    assert first_session_id == session_id

    view
    |> element("form[phx-change='set_group_filter']")
    |> render_change(%{"group_filter" => "z2m"})

    view
    |> element("form[phx-change='set_light_filter']")
    |> render_change(%{"light_filter" => "hue"})

    {:ok, view_reloaded, html_reloaded} = live(conn, "/lights")
    reloaded_session_id = :sys.get_state(view_reloaded.pid).socket.assigns.filter_session_id
    assert first_session_id == reloaded_session_id

    assert html_reloaded =~ ~r/<option value="z2m" selected(?:="selected")?>Z2M<\/option>/
    assert html_reloaded =~ ~r/<option value="hue" selected(?:="selected")?>Hue<\/option>/
  end

  test "z2m light edit modal shows actual kelvin override fields", %{conn: conn} do
    room = Repo.insert!(%Room{name: "Dining"})

    bridge =
      Repo.insert!(%Bridge{
        name: "Z2M Bridge",
        type: :z2m,
        host: "192.168.1.83",
        credentials: %{"broker_port" => 1883}
      })

    light =
      Repo.insert!(%Light{
        name: "Dining Strip",
        display_name: "Dining Strip",
        source: :z2m,
        source_id: "dining.strip",
        bridge_id: bridge.id,
        room_id: room.id,
        supports_temp: true,
        reported_min_kelvin: 2000,
        reported_max_kelvin: 6500
      })

    {:ok, view, _html} = live(conn, "/lights")

    view
    |> element("#light-#{light.id} button[aria-label='Edit light name']")
    |> render_click()

    rendered = render(view)

    assert rendered =~ "Actual min kelvin"
    assert rendered =~ "Actual max kelvin"
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

  defp clear_light_states(light_id) do
    if :ets.whereis(:hueworks_control_state) != :undefined do
      :ets.delete(:hueworks_control_state, {:light, light_id})
    end

    if :ets.whereis(:hueworks_desired_state) != :undefined do
      :ets.delete(:hueworks_desired_state, {:light, light_id})
    end
  end
end
