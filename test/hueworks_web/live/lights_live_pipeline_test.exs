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

  test "manual group toggle replans stale physical members via reconcile diff",
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
        source_id: "light-a-reconcile",
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
        source_id: "light-b-reconcile",
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
        source_id: "group-kitchen-reconcile",
        bridge_id: bridge.id,
        room_id: room.id,
        supports_temp: true,
        reported_min_kelvin: 2000,
        reported_max_kelvin: 6500
      })

    Repo.insert!(%GroupLight{group_id: group.id, light_id: light_a.id})
    Repo.insert!(%GroupLight{group_id: group.id, light_id: light_b.id})

    _ = DesiredState.put(:light, light_a.id, %{power: :on})
    _ = DesiredState.put(:light, light_b.id, %{power: :on})
    _ = State.put(:light, light_a.id, %{power: :off})
    _ = State.put(:light, light_b.id, %{power: :on})

    {:ok, view, _html} = live(conn, "/lights")

    view
    |> element("button[phx-click='toggle'][phx-value-type='group'][phx-value-id='#{group.id}']")
    |> render_click()

    drain_executor(executor_server)

    actions = Agent.get(actions_agent, & &1)

    assert [
             %{
               type: :group,
               id: group_id,
               desired: %{power: :on}
             }
           ] = actions

    assert group_id == group.id
    assert DesiredState.get(:light, light_a.id) == %{power: :on}
    assert DesiredState.get(:light, light_b.id) == %{power: :on}
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
             %{type: :light, id: light_id, desired: %{power: :on, brightness: 90, kelvin: 5000}}
           ] = actions

    assert light_id == light_a.id
    assert DesiredState.get(:light, light_a.id) == %{power: :on, brightness: 90, kelvin: 5000}
    assert DesiredState.get(:light, light_b.id) == %{power: :off}
  end

  test "manual power-on for a default-off scene light sends one on action with scene state",
       %{
         conn: conn,
         actions_agent: actions_agent,
         executor_server: executor_server
       } do
    room = Repo.insert!(%Room{name: "Den"})

    bridge =
      Repo.insert!(%Bridge{
        name: "Hue Bridge",
        type: :hue,
        host: "192.168.1.89",
        credentials: %{"api_key" => "test"}
      })

    light =
      Repo.insert!(%Light{
        name: "Reading Lamp",
        display_name: "Reading Lamp",
        source: :hue,
        source_id: "reading-lamp",
        bridge_id: bridge.id,
        room_id: room.id,
        supports_temp: true,
        reported_min_kelvin: 2000,
        reported_max_kelvin: 6500
      })

    {:ok, state} =
      Scenes.create_light_state("Soft", :manual, %{
        "brightness" => "42",
        "temperature" => "3100"
      })

    {:ok, scene} = Scenes.create_scene(%{name: "Evening", room_id: room.id})

    {:ok, _} =
      Scenes.replace_scene_components(scene, [
        %{
          name: "Evening Component",
          light_ids: [light.id],
          light_state_id: to_string(state.id),
          light_defaults: %{light.id => :force_off}
        }
      ])

    {:ok, _} = ActiveScenes.set_active(scene)

    _ = DesiredState.put(:light, light.id, %{power: :off})
    _ = State.put(:light, light.id, %{power: :off})

    {:ok, view, _html} = live(conn, "/lights")

    view
    |> element("button[phx-click='toggle'][phx-value-type='light'][phx-value-id='#{light.id}']")
    |> render_click()

    drain_executor(executor_server)

    actions = Agent.get(actions_agent, & &1)

    assert [
             %{type: :light, id: light_id, desired: %{power: :on, brightness: "42", kelvin: 3100}}
           ] = actions

    assert light_id == light.id
    assert DesiredState.get(:light, light.id) == %{power: :on, brightness: "42", kelvin: "3100"}
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

  test "extended-range z2m light keeps displayed low kelvin when ambiguous control-state update snaps upward",
       %{
         conn: conn,
         executor_server: executor_server
       } do
    room = Repo.insert!(%Room{name: "Media"})

    bridge =
      Repo.insert!(%Bridge{
        name: "Z2M Bridge",
        type: :z2m,
        host: "192.168.1.88",
        credentials: %{"broker_port" => 1883}
      })

    light =
      Repo.insert!(%Light{
        name: "TV Cabinet",
        display_name: "TV Cabinet",
        source: :z2m,
        source_id: "tv.cabinet",
        bridge_id: bridge.id,
        room_id: room.id,
        supports_temp: true,
        reported_min_kelvin: 2288,
        reported_max_kelvin: 6500,
        extended_kelvin_range: true
      })

    clear_light_states(light.id)

    {:ok, view, _html} = live(conn, "/lights")

    rendered = render(view)
    assert rendered =~ "TV Cabinet"
    assert rendered =~ "4250K"

    _ =
      render_hook(view, "set_color_temp", %{
        "type" => "light",
        "id" => Integer.to_string(light.id),
        "kelvin" => "2000"
      })

    drain_executor(executor_server)

    assert render(view) =~ "2000K"

    send(view.pid, {:control_state, :light, light.id, %{kelvin: 2700}})

    assert render(view) =~ "2000K"
  end

  test "light edit modal title uses display_name when present", %{conn: conn} do
    room = Repo.insert!(%Room{name: "Living Room"})

    bridge =
      Repo.insert!(%Bridge{
        name: "Hue Bridge",
        type: :hue,
        host: "192.168.1.85",
        credentials: %{"api_key" => "test"}
      })

    light =
      Repo.insert!(%Light{
        name: "living.room.floor_lamp",
        display_name: "Floor Lamp",
        source: :hue,
        source_id: "floor-lamp",
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

    assert has_element?(view, "div.hw-modal h3", "Floor Lamp")
    refute has_element?(view, "div.hw-modal h3", "living.room.floor_lamp")
  end

  test "light edit modal can link a light to another light", %{conn: conn} do
    room = Repo.insert!(%Room{name: "Kitchen"})

    bridge =
      Repo.insert!(%Bridge{
        name: "Mixed Bridge",
        type: :ha,
        host: "192.168.1.86",
        credentials: %{"token" => "test"}
      })

    target =
      Repo.insert!(%Light{
        name: "kitchen.target",
        display_name: "Kitchen Target",
        source: :caseta,
        source_id: "caseta-1",
        bridge_id: bridge.id,
        room_id: room.id
      })

    light =
      Repo.insert!(%Light{
        name: "kitchen.duplicate",
        display_name: "Kitchen Duplicate",
        source: :ha,
        source_id: "light.kitchen_duplicate",
        bridge_id: bridge.id,
        room_id: room.id
      })

    {:ok, view, _html} = live(conn, "/lights")

    view
    |> element("#light-#{light.id} button[aria-label='Edit light name']")
    |> render_click()

    assert has_element?(view, "button[phx-click='show_link_selector']", "Link to Other Light")
    refute has_element?(view, "select[name='canonical_light_id']")

    view
    |> element("button[phx-click='show_link_selector']")
    |> render_click()

    assert has_element?(view, "select[name='canonical_light_id']")
    assert render(view) =~ "Kitchen Target"

    view
    |> element("form[phx-submit='save_edit_fields']")
    |> render_submit(%{"canonical_light_id" => Integer.to_string(target.id)})

    assert Repo.get!(Light, light.id).canonical_light_id == target.id
  end

  test "show linked toggle reveals linked lights", %{conn: conn} do
    room = Repo.insert!(%Room{name: "Office"})

    bridge =
      Repo.insert!(%Bridge{
        name: "HA Bridge",
        type: :ha,
        host: "192.168.1.87",
        credentials: %{"token" => "test"}
      })

    root =
      Repo.insert!(%Light{
        name: "office.root",
        display_name: "Office Root",
        source: :caseta,
        source_id: "caseta-office",
        bridge_id: bridge.id,
        room_id: room.id
      })

    linked =
      Repo.insert!(%Light{
        name: "office.linked",
        display_name: "Office Linked",
        source: :ha,
        source_id: "light.office_linked",
        bridge_id: bridge.id,
        room_id: room.id,
        canonical_light_id: root.id
      })

    {:ok, view, _html} = live(conn, "/lights")

    refute has_element?(view, "#light-#{linked.id}")

    view
    |> element("form[phx-change='toggle_light_linked']")
    |> render_change(%{"show_linked_lights" => "true"})

    assert has_element?(view, "#light-#{linked.id}")
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
