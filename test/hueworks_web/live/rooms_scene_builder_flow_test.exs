defmodule Hueworks.RoomsSceneBuilderFlowTest do
  use HueworksWeb.ConnCase, async: false

  import Ecto.Query, only: [from: 2]
  import Phoenix.LiveViewTest

  alias Hueworks.Repo
  alias Hueworks.Control.State

  alias Hueworks.Schemas.{
    ActiveScene,
    Bridge,
    Group,
    GroupLight,
    Light,
    Room,
    Scene,
    SceneComponent,
    SceneComponentLight
  }

  defp insert_room do
    Repo.insert!(%Room{name: "Studio", metadata: %{}})
  end

  defp insert_bridge do
    Repo.insert!(%Bridge{
      type: :hue,
      name: "Hue Bridge",
      host: "10.0.0.230",
      credentials: %{"api_key" => "key"},
      import_complete: false,
      enabled: true
    })
  end

  defp insert_light(room, bridge, attrs) do
    defaults = %{
      name: "Light",
      source: :hue,
      source_id: Integer.to_string(System.unique_integer([:positive])),
      bridge_id: bridge.id,
      room_id: room.id,
      metadata: %{}
    }

    Repo.insert!(struct(Light, Map.merge(defaults, attrs)))
  end

  defp insert_group(room, bridge, attrs) do
    defaults = %{
      name: "Group",
      source: :hue,
      source_id: Integer.to_string(System.unique_integer([:positive])),
      bridge_id: bridge.id,
      room_id: room.id,
      metadata: %{}
    }

    Repo.insert!(struct(Group, Map.merge(defaults, attrs)))
  end

  defp insert_group_light(group, light) do
    Repo.insert!(%GroupLight{group_id: group.id, light_id: light.id})
  end

  test "rooms page add-scene action navigates to scene editor", %{conn: conn} do
    room = insert_room()

    {:ok, view, _html} = live(conn, "/rooms")

    assert {:error, {:live_redirect, %{to: to}}} =
             view
             |> element("#room-#{room.id} .hw-card-title button[phx-click='open_scene_new']")
             |> render_click()

    assert to == "/rooms/#{room.id}/scenes/new"
  end

  test "rooms page edit-scene action navigates to scene editor", %{conn: conn} do
    room = insert_room()
    {:ok, scene} = Hueworks.Scenes.create_scene(%{name: "Chill", room_id: room.id})

    {:ok, view, _html} = live(conn, "/rooms")

    assert {:error, {:live_redirect, %{to: to}}} =
             view
             |> element("#room-#{room.id} [phx-click='open_scene_edit']")
             |> render_click()

    assert to == "/rooms/#{room.id}/scenes/#{scene.id}/edit"
  end

  test "rooms page shows active scenes and toggles activate button to deactivate", %{conn: conn} do
    room = insert_room()
    {:ok, scene} = Hueworks.Scenes.create_scene(%{name: "Chill", room_id: room.id})

    {:ok, view, _html} = live(conn, "/rooms")

    assert has_element?(
             view,
             "#room-#{room.id} button[phx-click='activate_scene'][phx-value-id='#{scene.id}']",
             "Activate"
           )

    view
    |> element("#room-#{room.id} button[phx-click='activate_scene'][phx-value-id='#{scene.id}']")
    |> render_click()

    assert has_element?(
             view,
             "#room-#{room.id} button[phx-click='activate_scene'][phx-value-id='#{scene.id}']",
             "Deactivate"
           )

    assert has_element?(view, "#room-#{room.id} .hw-muted", "Active")
    assert Repo.get_by!(ActiveScene, room_id: room.id).scene_id == scene.id
  end

  test "clicking deactivate removes active_scene entry", %{conn: conn} do
    room = insert_room()
    {:ok, scene} = Hueworks.Scenes.create_scene(%{name: "Chill", room_id: room.id})
    {:ok, _} = Hueworks.ActiveScenes.set_active(scene)

    {:ok, view, _html} = live(conn, "/rooms")

    assert has_element?(
             view,
             "#room-#{room.id} button[phx-click='activate_scene'][phx-value-id='#{scene.id}']",
             "Deactivate"
           )

    view
    |> element("#room-#{room.id} button[phx-click='activate_scene'][phx-value-id='#{scene.id}']")
    |> render_click()

    assert has_element?(
             view,
             "#room-#{room.id} button[phx-click='activate_scene'][phx-value-id='#{scene.id}']",
             "Activate"
           )

    refute Repo.get_by(ActiveScene, room_id: room.id)
  end

  test "active scene occupancy toggle flips room occupancy state for testing", %{conn: conn} do
    room = insert_room()
    {:ok, scene} = Hueworks.Scenes.create_scene(%{name: "Night", room_id: room.id})
    {:ok, _} = Hueworks.ActiveScenes.set_active(scene)

    {:ok, view, _html} = live(conn, "/rooms")

    assert has_element?(
             view,
             "#room-#{room.id} button[phx-click='toggle_occupancy'][phx-value-room_id='#{room.id}']",
             "Occupied"
           )

    view
    |> element(
      "#room-#{room.id} button[phx-click='toggle_occupancy'][phx-value-room_id='#{room.id}']"
    )
    |> render_click()

    assert has_element?(
             view,
             "#room-#{room.id} button[phx-click='toggle_occupancy'][phx-value-room_id='#{room.id}']",
             "Unoccupied"
           )

    assert Repo.get!(Room, room.id).occupied == false
  end

  test "occupancy toggle should still flip back to occupied after a manual power toggle",
       %{conn: conn} do
    room = insert_room()
    bridge = insert_bridge()
    light = insert_light(room, bridge, %{name: "Path Light"})

    {:ok, state} =
      Hueworks.Scenes.create_manual_light_state("Night Path", %{
        "brightness" => "10",
        "temperature" => "2200"
      })

    {:ok, scene} = Hueworks.Scenes.create_scene(%{name: "Night", room_id: room.id})

    {:ok, _} =
      Hueworks.Scenes.replace_scene_components(scene, [
        %{
          name: "Component 1",
          light_ids: [light.id],
          light_state_id: to_string(state.id),
          light_defaults: %{light.id => :follow_occupancy}
        }
      ])

    {:ok, _} = Hueworks.ActiveScenes.set_active(scene)

    {:ok, view, _html} = live(conn, "/rooms")

    view
    |> element(
      "#room-#{room.id} button[phx-click='toggle_occupancy'][phx-value-room_id='#{room.id}']"
    )
    |> render_click()

    assert has_element?(
             view,
             "#room-#{room.id} button[phx-click='toggle_occupancy'][phx-value-room_id='#{room.id}']",
             "Unoccupied"
           )

    _ = State.put(:light, light.id, %{power: :on, brightness: 10, kelvin: 2200})

    assert Repo.get_by!(ActiveScene, room_id: room.id).scene_id == scene.id

    view
    |> element(
      "#room-#{room.id} button[phx-click='toggle_occupancy'][phx-value-room_id='#{room.id}']"
    )
    |> render_click()

    assert has_element?(
             view,
             "#room-#{room.id} button[phx-click='toggle_occupancy'][phx-value-room_id='#{room.id}']",
             "Occupied"
           )
  end

  test "creates a scene with components, lights, and manual light state via the UI", %{conn: conn} do
    room = insert_room()
    bridge = insert_bridge()
    light1 = insert_light(room, bridge, %{name: "Lamp"})
    light2 = insert_light(room, bridge, %{name: "Ceiling"})
    group = insert_group(room, bridge, %{name: "All"})
    insert_group_light(group, light1)
    insert_group_light(group, light2)

    {:ok, view, _html} = live(conn, "/rooms/#{room.id}/scenes/new")

    view
    |> form("form[phx-change='select_light_state'][data-component-id='1']", %{
      "component_id" => "1",
      "light_state_id" => "new"
    })
    |> render_change()

    view
    |> form("form[phx-change='select_light_state_name'][data-component-id='1']", %{
      "name" => "Warm"
    })
    |> render_change()

    view
    |> form("form[phx-change='update_light_state_form'][data-component-id='1']", %{
      "component_id" => "1",
      "brightness" => "55",
      "temperature" => "3000"
    })
    |> render_change()

    view
    |> element("button[phx-click='save_light_state_name'][phx-value-component_id='1']")
    |> render_click()

    view
    |> form("form[phx-change='select_group'][data-component-id='1']", %{
      "group_id" => Integer.to_string(group.id)
    })
    |> render_change()

    view
    |> element("button[phx-click='add_group'][phx-value-component_id='1']")
    |> render_click()

    view
    |> element(
      "button[phx-click='toggle_light_default_power'][phx-value-component_id='1'][phx-value-light_id='#{light1.id}']"
    )
    |> render_click()

    view
    |> form("form[phx-change='update_scene']", %{"name" => "Chill"})
    |> render_change()

    assert {:error, {:live_redirect, %{to: "/rooms"}}} =
             view
             |> element("button[phx-click='save_scene']")
             |> render_click()

    scene =
      Repo.one(from(s in Scene, where: s.room_id == ^room.id and s.name == "Chill"))

    assert scene

    scene_component =
      Repo.one(
        from(sc in SceneComponent,
          where: sc.scene_id == ^scene.id,
          preload: [:lights, :light_state]
        )
      )

    assert Enum.sort(Enum.map(scene_component.lights, & &1.id)) ==
             Enum.sort([light1.id, light2.id])

    assert scene_component.light_state.type == :manual
    assert scene_component.light_state.name == "Warm"
    assert scene_component.light_state.config["brightness"] == 55
    assert scene_component.light_state.config["temperature"] == 3000

    join_count =
      Repo.aggregate(
        from(scl in SceneComponentLight,
          join: sc in SceneComponent,
          on: sc.id == scl.scene_component_id,
          where: sc.scene_id == ^scene.id
        ),
        :count
      )

    assert join_count == 2

    default_power_by_light =
      Repo.all(
        from(scl in SceneComponentLight,
          join: sc in SceneComponent,
          on: sc.id == scl.scene_component_id,
          where: sc.scene_id == ^scene.id,
          select: {scl.light_id, scl.default_power}
        )
      )
      |> Map.new()

    assert default_power_by_light[light1.id] == :force_off
    assert default_power_by_light[light2.id] == :force_on
  end

  test "editing a scene updates components and light state via the UI", %{conn: conn} do
    room = insert_room()
    bridge = insert_bridge()
    light1 = insert_light(room, bridge, %{name: "Lamp"})
    light2 = insert_light(room, bridge, %{name: "Ceiling"})
    group = insert_group(room, bridge, %{name: "All"})
    insert_group_light(group, light1)
    insert_group_light(group, light2)

    {:ok, scene} = Hueworks.Scenes.create_scene(%{name: "Chill", room_id: room.id})
    {:ok, state} = Hueworks.Scenes.create_manual_light_state("Warm")

    {:ok, _} =
      Hueworks.Scenes.replace_scene_components(scene, [
        %{name: "Component 1", light_ids: [light1.id], light_state_id: to_string(state.id)}
      ])

    {:ok, view, _html} = live(conn, "/rooms/#{room.id}/scenes/#{scene.id}/edit")

    view
    |> form("form[phx-change='select_light'][data-component-id='1']", %{
      "light_id" => Integer.to_string(light2.id)
    })
    |> render_change()

    view
    |> element("button[phx-click='add_light'][phx-value-component_id='1']")
    |> render_click()

    view
    |> form("form[phx-change='select_light_state'][data-component-id='1']", %{
      "component_id" => "1",
      "light_state_id" => "new"
    })
    |> render_change()

    view
    |> form("form[phx-change='select_light_state_name'][data-component-id='1']", %{
      "name" => "Bright"
    })
    |> render_change()

    view
    |> form("form[phx-change='update_light_state_form'][data-component-id='1']", %{
      "component_id" => "1",
      "brightness" => "70",
      "temperature" => "3600"
    })
    |> render_change()

    view
    |> element("button[phx-click='save_light_state_name'][phx-value-component_id='1']")
    |> render_click()

    view
    |> form("form[phx-change='update_scene']", %{"name" => "Chill Updated"})
    |> render_change()

    assert {:error, {:live_redirect, %{to: "/rooms"}}} =
             view
             |> element("button[phx-click='save_scene']")
             |> render_click()

    updated =
      Repo.one(
        from(s in Scene, where: s.room_id == ^room.id and s.display_name == "Chill Updated")
      )

    assert updated

    scene_component =
      Repo.one(
        from(sc in SceneComponent,
          where: sc.scene_id == ^updated.id,
          preload: [:lights, :light_state]
        )
      )

    assert Enum.sort(Enum.map(scene_component.lights, & &1.id)) ==
             Enum.sort([light1.id, light2.id])

    assert scene_component.light_state.name == "Bright"
    assert scene_component.light_state.config["brightness"] == 70
    assert scene_component.light_state.config["temperature"] == 3600
  end

  test "circadian state form persists all circadian config inputs", %{conn: conn} do
    room = insert_room()
    bridge = insert_bridge()
    light1 = insert_light(room, bridge, %{name: "Lamp"})
    light2 = insert_light(room, bridge, %{name: "Ceiling"})
    group = insert_group(room, bridge, %{name: "All"})
    insert_group_light(group, light1)
    insert_group_light(group, light2)

    {:ok, view, _html} = live(conn, "/rooms/#{room.id}/scenes/new")

    view
    |> form("form[phx-change='select_group'][data-component-id='1']", %{
      "group_id" => Integer.to_string(group.id)
    })
    |> render_change()

    view
    |> element("button[phx-click='add_group'][phx-value-component_id='1']")
    |> render_click()

    view
    |> form("form[phx-change='select_light_state'][data-component-id='1']", %{
      "component_id" => "1",
      "light_state_id" => "new_circadian"
    })
    |> render_change()

    view
    |> form("form[phx-change='update_light_state_form'][data-component-id='1']", %{
      "component_id" => "1",
      "min_brightness" => "5",
      "max_brightness" => "95",
      "min_color_temp" => "2100",
      "max_color_temp" => "5000",
      "sunrise_time" => "06:30:00",
      "min_sunrise_time" => "05:45:00",
      "max_sunrise_time" => "07:00:00",
      "sunrise_offset" => "-900",
      "sunset_time" => "19:30:00",
      "min_sunset_time" => "18:45:00",
      "max_sunset_time" => "20:15:00",
      "sunset_offset" => "1200",
      "brightness_mode" => "linear",
      "brightness_mode_time_dark" => "1200",
      "brightness_mode_time_light" => "5400"
    })
    |> render_change()

    view
    |> form("form[phx-change='select_light_state_name'][data-component-id='1']", %{
      "name" => "Circadian Day"
    })
    |> render_change()

    view
    |> element("button[phx-click='save_light_state_name'][phx-value-component_id='1']")
    |> render_click()

    view
    |> form("form[phx-change='update_scene']", %{"name" => "Circadian Scene"})
    |> render_change()

    assert {:error, {:live_redirect, %{to: "/rooms"}}} =
             view
             |> element("button[phx-click='save_scene']")
             |> render_click()

    scene =
      Repo.one(from(s in Scene, where: s.room_id == ^room.id and s.name == "Circadian Scene"))

    component =
      Repo.one(
        from(sc in SceneComponent, where: sc.scene_id == ^scene.id, preload: [:light_state])
      )

    state = component.light_state
    assert state.type == :circadian
    assert state.name == "Circadian Day"

    assert state.config["min_brightness"] == 5
    assert state.config["max_brightness"] == 95
    assert state.config["min_color_temp"] == 2100
    assert state.config["max_color_temp"] == 5000
    assert state.config["sunrise_time"] == "06:30:00"
    assert state.config["min_sunrise_time"] == "05:45:00"
    assert state.config["max_sunrise_time"] == "07:00:00"
    assert state.config["sunrise_offset"] == -900
    assert state.config["sunset_time"] == "19:30:00"
    assert state.config["min_sunset_time"] == "18:45:00"
    assert state.config["max_sunset_time"] == "20:15:00"
    assert state.config["sunset_offset"] == 1200
    assert state.config["brightness_mode"] == "linear"
    assert state.config["brightness_mode_time_dark"] == 1200
    assert state.config["brightness_mode_time_light"] == 5400
  end

  test "saving a scene without a saved light state shows a validation error", %{conn: conn} do
    room = insert_room()
    bridge = insert_bridge()
    light1 = insert_light(room, bridge, %{name: "Lamp"})
    light2 = insert_light(room, bridge, %{name: "Ceiling"})
    group = insert_group(room, bridge, %{name: "All"})
    insert_group_light(group, light1)
    insert_group_light(group, light2)

    {:ok, view, _html} = live(conn, "/rooms/#{room.id}/scenes/new")

    view
    |> form("form[phx-change='select_group'][data-component-id='1']", %{
      "group_id" => Integer.to_string(group.id)
    })
    |> render_change()

    view
    |> element("button[phx-click='add_group'][phx-value-component_id='1']")
    |> render_click()

    view
    |> form("form[phx-change='update_scene']", %{"name" => "Off Scene"})
    |> render_change()

    view
    |> element("button[phx-click='save_scene']")
    |> render_click()

    assert has_element?(
             view,
             ".hw-error",
             "Each component must use a saved manual or circadian light state before saving."
           )

    refute Repo.one(from(s in Scene, where: s.room_id == ^room.id and s.name == "Off Scene"))
  end

  test "deleting a light state currently used by a scene is blocked", %{conn: conn} do
    room = insert_room()
    bridge = insert_bridge()
    light1 = insert_light(room, bridge, %{name: "Lamp"})
    light2 = insert_light(room, bridge, %{name: "Ceiling"})

    {:ok, state} = Hueworks.Scenes.create_manual_light_state("Solo")
    {:ok, scene} = Hueworks.Scenes.create_scene(%{name: "Chill", room_id: room.id})

    {:ok, _} =
      Hueworks.Scenes.replace_scene_components(scene, [
        %{
          name: "Component 1",
          light_ids: [light1.id, light2.id],
          light_state_id: to_string(state.id)
        }
      ])

    {:ok, view, _html} = live(conn, "/rooms/#{room.id}/scenes/#{scene.id}/edit")

    view
    |> element("button[phx-click='delete_light_state'][phx-value-component_id='1']")
    |> render_click()

    assert has_element?(view, ".hw-error", "Light state is in use by other scenes.")
    assert Hueworks.Repo.get(Hueworks.Schemas.LightState, state.id)
  end

  test "saving with unassigned lights shows a validation error banner", %{conn: conn} do
    room = insert_room()
    bridge = insert_bridge()
    _light1 = insert_light(room, bridge, %{name: "Lamp"})
    _light2 = insert_light(room, bridge, %{name: "Ceiling"})

    {:ok, view, _html} = live(conn, "/rooms/#{room.id}/scenes/new")

    view
    |> form("form[phx-change='update_scene']", %{"name" => "Blocked"})
    |> render_change()

    view
    |> element("button[phx-click='save_scene']")
    |> render_click()

    assert has_element?(view, ".hw-error", "Assign all lights once before saving.")
  end

  test "disabled room lights are excluded from scene builder options and unassigned counts",
       %{conn: conn} do
    room = insert_room()
    bridge = insert_bridge()
    _enabled = insert_light(room, bridge, %{name: "Lamp", enabled: true})
    _disabled = insert_light(room, bridge, %{name: "Disabled", enabled: false})

    {:ok, view, _html} = live(conn, "/rooms/#{room.id}/scenes/new")

    html = render(view)

    assert html =~ "option value=\"\">Select light</option>"
    assert html =~ "Lamp"
    refute html =~ "Disabled"
    assert html =~ "Unassigned lights: 1"
  end

  test "scene editor uses a click save button instead of nested save form", %{conn: conn} do
    room = insert_room()
    bridge = insert_bridge()
    _light1 = insert_light(room, bridge, %{name: "Lamp"})
    _light2 = insert_light(room, bridge, %{name: "Ceiling"})

    {:ok, view, _html} = live(conn, "/rooms/#{room.id}/scenes/new")

    refute has_element?(view, "form[phx-submit='save_scene']")
    assert has_element?(view, "button[phx-click='save_scene']")
  end

  test "manual sliders initialize when reopening edit page", %{conn: conn} do
    room = insert_room()
    bridge = insert_bridge()
    light1 = insert_light(room, bridge, %{name: "Lamp"})
    light2 = insert_light(room, bridge, %{name: "Ceiling"})
    group = insert_group(room, bridge, %{name: "All"})
    insert_group_light(group, light1)
    insert_group_light(group, light2)

    {:ok, view, _html} = live(conn, "/rooms/#{room.id}/scenes/new")

    view
    |> form("form[phx-change='select_group'][data-component-id='1']", %{
      "group_id" => Integer.to_string(group.id)
    })
    |> render_change()

    view
    |> element("button[phx-click='add_group'][phx-value-component_id='1']")
    |> render_click()

    view
    |> form("form[phx-change='select_light_state'][data-component-id='1']", %{
      "component_id" => "1",
      "light_state_id" => "new"
    })
    |> render_change()

    view
    |> form("form[phx-change='select_light_state_name'][data-component-id='1']", %{
      "name" => "Warm"
    })
    |> render_change()

    view
    |> form("form[phx-change='update_light_state_form'][data-component-id='1']", %{
      "component_id" => "1",
      "brightness" => "65",
      "temperature" => "3100"
    })
    |> render_change()

    view
    |> element("button[phx-click='save_light_state_name'][phx-value-component_id='1']")
    |> render_click()

    view
    |> form("form[phx-change='update_scene']", %{"name" => "Slider Scene"})
    |> render_change()

    assert {:error, {:live_redirect, %{to: "/rooms"}}} =
             view
             |> element("button[phx-click='save_scene']")
             |> render_click()

    scene = Repo.one(from(s in Scene, where: s.room_id == ^room.id and s.name == "Slider Scene"))
    assert scene

    {:ok, edit_view, _html} = live(conn, "/rooms/#{room.id}/scenes/#{scene.id}/edit")
    html = render(edit_view)

    assert html =~ ~r/name=\"brightness\"[^>]*value=\"65\"/
    assert html =~ ~r/name=\"temperature\"[^>]*value=\"3100\"/
  end
end
