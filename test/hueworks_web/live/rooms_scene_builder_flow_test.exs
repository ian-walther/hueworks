defmodule Hueworks.RoomsSceneBuilderFlowTest do
  use HueworksWeb.ConnCase, async: false

  import Ecto.Query, only: [from: 2]
  import Phoenix.LiveViewTest

  alias Hueworks.Repo
  alias Hueworks.Control.State
  alias Hueworks.Control.DesiredState

  alias Hueworks.Schemas.{
    ActiveScene,
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
    insert_bridge!(%{
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

  defp eventually(fun, attempts \\ 20)

  defp eventually(fun, attempts) when attempts > 0 do
    if fun.() do
      true
    else
      Process.sleep(25)
      eventually(fun, attempts - 1)
    end
  end

  defp eventually(_fun, 0), do: false

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

  test "rooms page clone-scene action navigates to a prefilled new scene editor", %{conn: conn} do
    room = insert_room()
    {:ok, scene} = Hueworks.Scenes.create_scene(%{name: "Chill", room_id: room.id})

    {:ok, view, _html} = live(conn, "/rooms")

    assert {:error, {:live_redirect, %{to: to}}} =
             view
             |> element("#room-#{room.id} [phx-click='open_scene_clone']")
             |> render_click()

    assert to == "/rooms/#{room.id}/scenes/new?clone_scene_id=#{scene.id}"
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

  test "rooms page updates active scene status when scene changes live", %{conn: conn} do
    room = insert_room()
    {:ok, scene} = Hueworks.Scenes.create_scene(%{name: "Chill", room_id: room.id})

    {:ok, view, _html} = live(conn, "/rooms")

    assert has_element?(
             view,
             "#room-#{room.id} button[phx-click='activate_scene'][phx-value-id='#{scene.id}']",
             "Activate"
           )

    {:ok, _} = Hueworks.ActiveScenes.set_active(scene)

    assert eventually(fn ->
             has_element?(
               view,
               "#room-#{room.id} button[phx-click='activate_scene'][phx-value-id='#{scene.id}']",
               "Deactivate"
             ) and has_element?(view, "#room-#{room.id} .hw-muted", "Active")
           end)

    :ok = Hueworks.ActiveScenes.clear_for_room(room.id)

    assert eventually(fn ->
             has_element?(
               view,
               "#room-#{room.id} button[phx-click='activate_scene'][phx-value-id='#{scene.id}']",
               "Activate"
             ) and not has_element?(view, "#room-#{room.id} .hw-muted", "Active")
           end)
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

    {:ok, state} =
      Hueworks.Scenes.create_manual_light_state("Warm", %{
        "brightness" => "55",
        "temperature" => "3000"
      })

    {:ok, view, _html} = live(conn, "/rooms/#{room.id}/scenes/new")

    view
    |> form("form[phx-change='select_light_state'][data-component-id='1']", %{
      "component_id" => "1",
      "light_state_id" => Integer.to_string(state.id)
    })
    |> render_change()

    view
    |> form("form[phx-change='select_group'][data-component-id='1']", %{
      "group_id" => Integer.to_string(group.id)
    })
    |> render_change()

    view
    |> element(
      "button[phx-click='toggle_group_expanded'][phx-value-component_id='1'][phx-value-group_id='#{group.id}']"
    )
    |> render_click()

    view
    |> element(
      "button[phx-click='toggle_light_default_power'][phx-value-component_id='1'][phx-value-light_id='#{light1.id}']"
    )
    |> render_click()

    view
    |> form("form[phx-change='update_scene']", %{"name" => "Chill"})
    |> render_change()

    view
    |> element("button[phx-click='save_scene']")
    |> render_click()

    scene =
      Repo.one(from(s in Scene, where: s.room_id == ^room.id and s.name == "Chill"))

    assert_patch(view, "/rooms/#{room.id}/scenes/#{scene.id}/edit")

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

    assert scene_component.light_state_id == state.id
    assert scene_component.light_state.type == :manual

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

    {:ok, state} =
      Hueworks.Scenes.create_manual_light_state("Warm", %{
        "brightness" => "55",
        "temperature" => "3000"
      })

    {:ok, bright} =
      Hueworks.Scenes.create_manual_light_state("Bright", %{
        "brightness" => "70",
        "temperature" => "3600"
      })

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
    |> form("form[phx-change='select_light_state'][data-component-id='1']", %{
      "component_id" => "1",
      "light_state_id" => Integer.to_string(bright.id)
    })
    |> render_change()

    view
    |> form("form[phx-change='update_scene']", %{"name" => "Chill Updated"})
    |> render_change()

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

    assert scene_component.light_state_id == bright.id
    assert scene_component.light_state.name == "Bright"
  end

  test "creates a scene with an embedded custom manual light state via the UI", %{conn: conn} do
    room = insert_room()
    bridge = insert_bridge()
    light = insert_light(room, bridge, %{name: "Lamp"})

    {:ok, view, _html} = live(conn, "/rooms/#{room.id}/scenes/new")

    view
    |> form("form[phx-change='select_light'][data-component-id='1']", %{
      "light_id" => Integer.to_string(light.id)
    })
    |> render_change()

    view
    |> form("form[phx-change='select_light_state'][data-component-id='1']", %{
      "component_id" => "1",
      "light_state_id" => "custom"
    })
    |> render_change()

    view
    |> form("form[phx-change='update_embedded_manual_config'][data-component-id='1']", %{
      "component_id" => "1",
      "mode" => "temperature",
      "brightness" => "42",
      "temperature" => "2800"
    })
    |> render_change()

    view
    |> form("form[phx-change='update_scene']", %{"name" => "Custom Scene"})
    |> render_change()

    view
    |> element("button[phx-click='save_scene']")
    |> render_click()

    scene =
      Repo.one(from(s in Scene, where: s.room_id == ^room.id and s.name == "Custom Scene"))

    component = Repo.one(from(sc in SceneComponent, where: sc.scene_id == ^scene.id))

    assert_patch(view, "/rooms/#{room.id}/scenes/#{scene.id}/edit")
    assert component.light_state_id == nil

    assert component.embedded_manual_config == %{
             "brightness" => 42,
             "mode" => "temperature",
             "temperature" => 2800
           }
  end

  test "saved scenes can be activated from the editor and active scene edits refresh desired state",
       %{conn: conn} do
    room = insert_room()
    bridge = insert_bridge()
    light = insert_light(room, bridge, %{name: "Lamp", supports_temp: true})

    {:ok, scene} = Hueworks.Scenes.create_scene(%{name: "Custom Scene", room_id: room.id})

    {:ok, _} =
      Hueworks.Scenes.replace_scene_components(scene, [
        %{
          name: "Component 1",
          light_ids: [light.id],
          embedded_manual_config: %{
            "mode" => "temperature",
            "brightness" => "35",
            "temperature" => "2700"
          }
        }
      ])

    {:ok, view, _html} = live(conn, "/rooms/#{room.id}/scenes/#{scene.id}/edit")

    assert has_element?(view, "#scene-toggle-activation", "Activate")

    view
    |> element("#scene-toggle-activation")
    |> render_click()

    assert has_element?(view, "#scene-toggle-activation", "Deactivate")
    assert Hueworks.ActiveScenes.get_for_room(room.id).scene_id == scene.id
    assert DesiredState.get(:light, light.id) == %{power: :on, brightness: 35, kelvin: 2700}

    view
    |> form("form[phx-change='select_light_state'][data-component-id='1']", %{
      "component_id" => "1",
      "light_state_id" => "custom"
    })
    |> render_change()

    view
    |> form("form[phx-change='update_embedded_manual_config'][data-component-id='1']", %{
      "component_id" => "1",
      "mode" => "temperature",
      "brightness" => "60",
      "temperature" => "3100"
    })
    |> render_change()

    view
    |> element("button[phx-click='save_scene']")
    |> render_click()

    assert DesiredState.get(:light, light.id) == %{power: :on, brightness: 60, kelvin: 3100}
    assert has_element?(view, "#scene-toggle-activation", "Deactivate")
  end

  test "editing an active scene can move a light from a circadian component into a manual color component",
       %{
         conn: conn
       } do
    room = insert_room()
    bridge = insert_bridge()

    light1 =
      insert_light(room, bridge, %{name: "Lamp 1", supports_color: true, supports_temp: true})

    light2 =
      insert_light(room, bridge, %{name: "Lamp 2", supports_color: true, supports_temp: true})

    {:ok, circadian} =
      Hueworks.Scenes.create_light_state("Circadian", :circadian, %{
        "sunrise_time" => "06:00:00",
        "sunset_time" => "18:00:00",
        "min_brightness" => 10,
        "max_brightness" => 90,
        "min_color_temp" => 2200,
        "max_color_temp" => 5000
      })

    {:ok, blue} =
      Hueworks.Scenes.create_manual_light_state("Blue", %{
        "mode" => "color",
        "brightness" => "75",
        "hue" => "210",
        "saturation" => "60"
      })

    {:ok, scene} = Hueworks.Scenes.create_scene(%{name: "Color Mix", room_id: room.id})

    {:ok, _} =
      Hueworks.Scenes.replace_scene_components(scene, [
        %{
          name: "Component 1",
          light_ids: [light1.id, light2.id],
          light_state_id: to_string(circadian.id)
        }
      ])

    {:ok, _} = Hueworks.ActiveScenes.set_active(scene)
    {:ok, _diff, _updated} = Hueworks.Scenes.activate_scene(scene.id)

    assert DesiredState.get(:light, light2.id)[:kelvin]

    {:ok, view, _html} = live(conn, "/rooms/#{room.id}/scenes/#{scene.id}/edit")

    view
    |> element("button[phx-click='add_component']")
    |> render_click()

    view
    |> element(
      "button[phx-click='remove_light'][phx-value-component_id='1'][phx-value-light_id='#{light2.id}']"
    )
    |> render_click()

    view
    |> form("form[phx-change='select_light'][data-component-id='2']", %{
      "component_id" => "2",
      "light_id" => Integer.to_string(light2.id)
    })
    |> render_change()

    view
    |> form("form[phx-change='select_light_state'][data-component-id='2']", %{
      "component_id" => "2",
      "light_state_id" => Integer.to_string(blue.id)
    })
    |> render_change()

    view
    |> element("button[phx-click='save_scene']")
    |> render_click()

    updated_scene = Repo.get!(Scene, scene.id)
    assert {:ok, _diff, _updated} = Hueworks.Scenes.refresh_active_scene(updated_scene.id)

    updated_scene =
      Repo.get!(Scene, scene.id)
      |> Repo.preload(scene_components: [:lights, :light_state])

    assert Enum.count(updated_scene.scene_components) == 2

    circadian_component =
      Enum.find(updated_scene.scene_components, fn component ->
        component.light_state_id == circadian.id
      end)

    color_component =
      Enum.find(updated_scene.scene_components, fn component ->
        component.light_state_id == blue.id
      end)

    assert Enum.map(circadian_component.lights, & &1.id) == [light1.id]
    assert Enum.map(color_component.lights, & &1.id) == [light2.id]

    desired = DesiredState.get(:light, light2.id)
    {expected_x, expected_y} = Hueworks.Color.hs_to_xy(210, 60)

    assert desired[:brightness] == 75
    assert_in_delta desired[:x], expected_x, 0.0001
    assert_in_delta desired[:y], expected_y, 0.0001
    refute Map.has_key?(desired, :kelvin)
  end

  test "cloning a scene preloads its inputs and saves a new copy", %{conn: conn} do
    room = insert_room()
    bridge = insert_bridge()
    light1 = insert_light(room, bridge, %{name: "Lamp", supports_color: true})
    light2 = insert_light(room, bridge, %{name: "Ceiling", supports_color: true})

    {:ok, warm} =
      Hueworks.Scenes.create_manual_light_state("Warm", %{
        "brightness" => "55",
        "temperature" => "3000"
      })

    {:ok, blue} =
      Hueworks.Scenes.create_manual_light_state("Blue", %{
        "mode" => "color",
        "brightness" => "75",
        "hue" => "210",
        "saturation" => "60"
      })

    {:ok, scene} = Hueworks.Scenes.create_scene(%{name: "Original", room_id: room.id})

    {:ok, _} =
      Hueworks.Scenes.replace_scene_components(scene, [
        %{
          name: "Component 1",
          light_ids: [light1.id],
          light_state_id: to_string(warm.id),
          light_defaults: %{light1.id => :force_off}
        },
        %{
          name: "Component 2",
          light_ids: [light2.id],
          light_state_id: to_string(blue.id),
          light_defaults: %{light2.id => :force_on}
        }
      ])

    {:ok, view, _html} = live(conn, "/rooms/#{room.id}/scenes/new?clone_scene_id=#{scene.id}")

    html = render(view)
    assert html =~ ~s(value="Original Copy")
    assert html =~ "Lamp"
    assert html =~ "Ceiling"
    assert html =~ "Warm"
    assert html =~ "Blue"

    view
    |> element("button[phx-click='save_scene']")
    |> render_click()

    clones =
      Repo.all(from(s in Scene, where: s.room_id == ^room.id, order_by: [asc: s.id]))

    assert Enum.count(clones) == 2

    cloned_scene = List.last(clones)
    refute cloned_scene.id == scene.id
    assert cloned_scene.name == "Original Copy"
    assert_patch(view, "/rooms/#{room.id}/scenes/#{cloned_scene.id}/edit")

    assert scene_component_fingerprint(cloned_scene.id) == scene_component_fingerprint(scene.id)
  end

  test "selecting an existing circadian state saves it on the scene component", %{conn: conn} do
    room = insert_room()
    bridge = insert_bridge()
    light1 = insert_light(room, bridge, %{name: "Lamp"})
    light2 = insert_light(room, bridge, %{name: "Ceiling"})
    group = insert_group(room, bridge, %{name: "All"})
    insert_group_light(group, light1)
    insert_group_light(group, light2)

    {:ok, state} =
      Hueworks.Scenes.create_light_state("Circadian Day", :circadian, %{
        "min_brightness" => 5,
        "max_brightness" => 95,
        "min_color_temp" => 2100,
        "max_color_temp" => 5000,
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

    {:ok, view, _html} = live(conn, "/rooms/#{room.id}/scenes/new")

    view
    |> form("form[phx-change='select_group'][data-component-id='1']", %{
      "group_id" => Integer.to_string(group.id)
    })
    |> render_change()

    view
    |> form("form[phx-change='select_light_state'][data-component-id='1']", %{
      "component_id" => "1",
      "light_state_id" => Integer.to_string(state.id)
    })
    |> render_change()

    view
    |> form("form[phx-change='update_scene']", %{"name" => "Circadian Scene"})
    |> render_change()

    view
    |> element("button[phx-click='save_scene']")
    |> render_click()

    scene =
      Repo.one(from(s in Scene, where: s.room_id == ^room.id and s.name == "Circadian Scene"))

    component =
      Repo.one(
        from(sc in SceneComponent, where: sc.scene_id == ^scene.id, preload: [:light_state])
      )

    assert_patch(view, "/rooms/#{room.id}/scenes/#{scene.id}/edit")
    assert component.light_state_id == state.id
    assert component.light_state.type == :circadian
    assert component.light_state.name == "Circadian Day"
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
    |> form("form[phx-change='update_scene']", %{"name" => "Off Scene"})
    |> render_change()

    view
    |> element("button[phx-click='save_scene']")
    |> render_click()

    assert has_element?(
             view,
             ".hw-flash-bar-error",
             "Each component must use a saved light state or custom manual state before saving."
           )

    refute Repo.one(from(s in Scene, where: s.room_id == ^room.id and s.name == "Off Scene"))
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

    assert has_element?(view, ".hw-flash-bar-error", "Assign all lights once before saving.")
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

  defp scene_component_fingerprint(scene_id) do
    Repo.all(
      from(sc in SceneComponent,
        where: sc.scene_id == ^scene_id,
        order_by: [asc: sc.name, asc: sc.id],
        preload: [:scene_component_lights]
      )
    )
    |> Enum.map(fn component ->
      %{
        name: component.name,
        light_state_id: component.light_state_id,
        lights:
          component.scene_component_lights
          |> Enum.map(&{&1.light_id, &1.default_power})
          |> Enum.sort()
      }
    end)
  end
end
