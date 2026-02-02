defmodule Hueworks.RoomsSceneBuilderFlowTest do
  use HueworksWeb.ConnCase, async: false

  import Ecto.Query, only: [from: 2]
  import Phoenix.LiveViewTest

  alias Hueworks.Repo

  alias Hueworks.Schemas.{
    Bridge,
    Group,
    GroupLight,
    Light,
    Room,
    Scene,
    SceneComponent,
    SceneComponentLight,
    LightState
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

  test "creates a scene with components, lights, and light state via the UI", %{conn: conn} do
    room = insert_room()
    bridge = insert_bridge()
    light1 = insert_light(room, bridge, %{name: "Lamp"})
    light2 = insert_light(room, bridge, %{name: "Ceiling"})
    group = insert_group(room, bridge, %{name: "All"})
    insert_group_light(group, light1)
    insert_group_light(group, light2)

    {:ok, view, _html} = live(conn, "/rooms")

    view
    |> element("#room-#{room.id} .hw-card-title button[phx-click='open_scene_new']")
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
    |> form("form[phx-change='update_scene']", %{"name" => "Chill"})
    |> render_change()

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
    assert Repo.aggregate(LightState, :count) >= 1
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

    {:ok, view, _html} = live(conn, "/rooms")

    view
    |> element("#room-#{room.id} [phx-click='open_scene_edit']")
    |> render_click()

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
    |> element("button[phx-click='save_light_state_name'][phx-value-component_id='1']")
    |> render_click()

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

    assert scene_component.light_state.name == "Bright"
  end

  test "creating a manual light state keeps the scene modal open", %{conn: conn} do
    room = insert_room()
    bridge = insert_bridge()
    light1 = insert_light(room, bridge, %{name: "Lamp"})
    light2 = insert_light(room, bridge, %{name: "Ceiling"})
    group = insert_group(room, bridge, %{name: "All"})
    insert_group_light(group, light1)
    insert_group_light(group, light2)

    {:ok, view, _html} = live(conn, "/rooms")

    view
    |> element("#room-#{room.id} .hw-card-title button[phx-click='open_scene_new']")
    |> render_click()

    view
    |> form("form[phx-change='select_light_state'][data-component-id='1']", %{
      "component_id" => "1",
      "light_state_id" => "new"
    })
    |> render_change()

    view
    |> form("form[phx-change='select_light_state_name'][data-component-id='1']", %{
      "name" => "Soft"
    })
    |> render_change()

    view
    |> element("button[phx-click='save_light_state_name'][phx-value-component_id='1']")
    |> render_click()

    html = render(view)

    assert html =~ "Add Scene"
    assert html =~ "hw-modal-backdrop"
  end

  test "deleting a manual light state removes it from the dropdown list", %{conn: conn} do
    room = insert_room()
    bridge = insert_bridge()
    light1 = insert_light(room, bridge, %{name: "Lamp"})
    light2 = insert_light(room, bridge, %{name: "Ceiling"})
    group = insert_group(room, bridge, %{name: "All"})
    insert_group_light(group, light1)
    insert_group_light(group, light2)

    {:ok, view, _html} = live(conn, "/rooms")

    view
    |> element("#room-#{room.id} .hw-card-title button[phx-click='open_scene_new']")
    |> render_click()

    view
    |> form("form[phx-change='select_light_state'][data-component-id='1']", %{
      "component_id" => "1",
      "light_state_id" => "new"
    })
    |> render_change()

    view
    |> form("form[phx-change='select_light_state_name'][data-component-id='1']", %{
      "name" => "Temp"
    })
    |> render_change()

    view
    |> element("button[phx-click='save_light_state_name'][phx-value-component_id='1']")
    |> render_click()

    state_id =
      Repo.one(from(ls in LightState, where: ls.name == "Temp", select: ls.id))

    view
    |> form("form[phx-change='select_light_state'][data-component-id='1']", %{
      "component_id" => "1",
      "light_state_id" => Integer.to_string(state_id)
    })
    |> render_change()

    view
    |> element("button[phx-click='delete_light_state'][phx-value-component_id='1']")
    |> render_click()

    refute has_element?(view, "select[name='light_state_id'] option[value='#{state_id}']")
  end

  test "deleting a light state used only by the current scene is allowed", %{conn: conn} do
    room = insert_room()
    bridge = insert_bridge()
    light1 = insert_light(room, bridge, %{name: "Lamp"})
    light2 = insert_light(room, bridge, %{name: "Ceiling"})
    group = insert_group(room, bridge, %{name: "All"})
    insert_group_light(group, light1)
    insert_group_light(group, light2)

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

    {:ok, view, _html} = live(conn, "/rooms")

    view
    |> element("#room-#{room.id} [phx-click='open_scene_edit']")
    |> render_click()

    view
    |> element("button[phx-click='delete_light_state'][phx-value-component_id='1']")
    |> render_click()

    refute has_element?(view, ".hw-error", "Light state is in use by other scenes.")
    refute has_element?(view, "select[name='light_state_id'] option[value='#{state.id}']")
    assert has_element?(view, "select[name='light_state_id'] option[value='off'][selected]")
    refute Hueworks.Repo.get(Hueworks.Schemas.LightState, state.id)
  end

  test "saving a scene with off light state succeeds", %{conn: conn} do
    room = insert_room()
    bridge = insert_bridge()
    light1 = insert_light(room, bridge, %{name: "Lamp"})
    light2 = insert_light(room, bridge, %{name: "Ceiling"})
    group = insert_group(room, bridge, %{name: "All"})
    insert_group_light(group, light1)
    insert_group_light(group, light2)

    {:ok, view, _html} = live(conn, "/rooms")

    view
    |> element("#room-#{room.id} .hw-card-title button[phx-click='open_scene_new']")
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
    |> form("form[phx-change='update_scene']", %{"name" => "Off Scene"})
    |> render_change()

    view
    |> element("button[phx-click='save_scene']")
    |> render_click()

    scene =
      Repo.one(from(s in Scene, where: s.room_id == ^room.id and s.name == "Off Scene"))

    assert scene

    scene_component =
      Repo.one(from(sc in SceneComponent, where: sc.scene_id == ^scene.id))

    off = Hueworks.Scenes.get_or_create_off_state()
    assert scene_component.light_state_id == off.id
  end

  test "delete light state defaults to off and still allows save after reopening modal", %{
    conn: conn
  } do
    room = insert_room()
    bridge = insert_bridge()
    light1 = insert_light(room, bridge, %{name: "Lamp"})
    light2 = insert_light(room, bridge, %{name: "Ceiling"})
    group = insert_group(room, bridge, %{name: "All"})
    insert_group_light(group, light1)
    insert_group_light(group, light2)

    {:ok, view, _html} = live(conn, "/rooms")

    view
    |> element("#room-#{room.id} .hw-card-title button[phx-click='open_scene_new']")
    |> render_click()

    view
    |> form("form[phx-change='select_light_state'][data-component-id='1']", %{
      "component_id" => "1",
      "light_state_id" => "new"
    })
    |> render_change()

    view
    |> form("form[phx-change='select_light_state_name'][data-component-id='1']", %{
      "name" => "Temp"
    })
    |> render_change()

    view
    |> element("button[phx-click='save_light_state_name'][phx-value-component_id='1']")
    |> render_click()

    state_id =
      Repo.one(from(ls in LightState, where: ls.name == "Temp", select: ls.id))

    view
    |> form("form[phx-change='select_light_state'][data-component-id='1']", %{
      "component_id" => "1",
      "light_state_id" => Integer.to_string(state_id)
    })
    |> render_change()

    view
    |> element("button[phx-click='delete_light_state'][phx-value-component_id='1']")
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
    |> element(".hw-modal-close")
    |> render_click()

    view
    |> element("#room-#{room.id} .hw-card-title button[phx-click='open_scene_new']")
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
    |> form("form[phx-change='update_scene']", %{"name" => "After Delete"})
    |> render_change()

    view
    |> element("button[phx-click='save_scene']")
    |> render_click()

    scene =
      Repo.one(from(s in Scene, where: s.room_id == ^room.id and s.name == "After Delete"))

    assert scene
  end

  test "editing an existing scene allows deleting its light state and saving", %{conn: conn} do
    room = insert_room()
    bridge = insert_bridge()
    light1 = insert_light(room, bridge, %{name: "Lamp"})
    light2 = insert_light(room, bridge, %{name: "Ceiling"})
    group = insert_group(room, bridge, %{name: "All"})
    insert_group_light(group, light1)
    insert_group_light(group, light2)

    {:ok, state} = Hueworks.Scenes.create_manual_light_state("Solo")
    {:ok, scene} = Hueworks.Scenes.create_scene(%{name: "Existing", room_id: room.id})

    {:ok, _} =
      Hueworks.Scenes.replace_scene_components(scene, [
        %{
          name: "Component 1",
          light_ids: [light1.id, light2.id],
          light_state_id: to_string(state.id)
        }
      ])

    {:ok, view, _html} = live(conn, "/rooms")

    view
    |> element("#room-#{room.id} [phx-click='open_scene_edit']")
    |> render_click()

    view
    |> element("button[phx-click='delete_light_state'][phx-value-component_id='1']")
    |> render_click()

    view
    |> form("form[phx-change='update_scene']", %{"name" => "Existing"})
    |> render_change()

    view
    |> element("button[phx-click='save_scene']")
    |> render_click()

    updated = Repo.get(Scene, scene.id)
    assert updated

    scene_component =
      Repo.one(from(sc in SceneComponent, where: sc.scene_id == ^scene.id))

    off = Hueworks.Scenes.get_or_create_off_state()
    assert scene_component.light_state_id == off.id
  end

  test "editing an existing scene can save without changes", %{conn: conn} do
    room = insert_room()
    bridge = insert_bridge()
    light1 = insert_light(room, bridge, %{name: "Lamp"})
    light2 = insert_light(room, bridge, %{name: "Ceiling"})
    group = insert_group(room, bridge, %{name: "All"})
    insert_group_light(group, light1)
    insert_group_light(group, light2)

    {:ok, state} = Hueworks.Scenes.create_manual_light_state("Solo")
    {:ok, scene} = Hueworks.Scenes.create_scene(%{name: "Existing", room_id: room.id})

    {:ok, _} =
      Hueworks.Scenes.replace_scene_components(scene, [
        %{
          name: "Component 1",
          light_ids: [light1.id, light2.id],
          light_state_id: to_string(state.id)
        }
      ])

    {:ok, view, _html} = live(conn, "/rooms")

    view
    |> element("#room-#{room.id} [phx-click='open_scene_edit']")
    |> render_click()

    view
    |> form("form[phx-change='update_scene']", %{"name" => "Existing"})
    |> render_change()

    view
    |> element("button[phx-click='save_scene']")
    |> render_click()

    refute has_element?(view, ".hw-modal-backdrop")
    assert Repo.get(Scene, scene.id)
  end

  test "saving with unassigned lights shows a validation error banner", %{conn: conn} do
    room = insert_room()
    bridge = insert_bridge()
    _light1 = insert_light(room, bridge, %{name: "Lamp"})
    _light2 = insert_light(room, bridge, %{name: "Ceiling"})

    {:ok, view, _html} = live(conn, "/rooms")

    view
    |> element("#room-#{room.id} .hw-card-title button[phx-click='open_scene_new']")
    |> render_click()

    view
    |> form("form[phx-change='update_scene']", %{"name" => "Blocked"})
    |> render_change()

    view
    |> element("button[phx-click='save_scene']")
    |> render_click()

    assert has_element?(view, ".hw-error", "Assign all lights once before saving.")
  end

  test "scene modal uses a click save button instead of nested save form", %{conn: conn} do
    room = insert_room()
    bridge = insert_bridge()
    _light1 = insert_light(room, bridge, %{name: "Lamp"})
    _light2 = insert_light(room, bridge, %{name: "Ceiling"})

    {:ok, view, _html} = live(conn, "/rooms")

    view
    |> element("#room-#{room.id} .hw-card-title button[phx-click='open_scene_new']")
    |> render_click()

    refute has_element?(view, "form[phx-submit='save_scene']")
    assert has_element?(view, "button[phx-click='save_scene']")
  end

  test "sliders initialize after saving a new light state on an off component", %{conn: conn} do
    room = insert_room()
    bridge = insert_bridge()
    light1 = insert_light(room, bridge, %{name: "Lamp"})
    light2 = insert_light(room, bridge, %{name: "Ceiling"})
    group = insert_group(room, bridge, %{name: "All"})
    insert_group_light(group, light1)
    insert_group_light(group, light2)

    {:ok, view, _html} = live(conn, "/rooms")

    view
    |> element("#room-#{room.id} .hw-card-title button[phx-click='open_scene_new']")
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
    |> form("form[phx-change='select_light_state'][data-component-id='1']", %{
      "component_id" => "1",
      "light_state_id" => "new"
    })
    |> render_change()

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

    view
    |> element("button[phx-click='save_scene']")
    |> render_click()

    scene = Repo.one(from(s in Scene, where: s.room_id == ^room.id and s.name == "Slider Scene"))
    assert scene

    view
    |> element("#room-#{room.id} [phx-click='open_scene_edit']")
    |> render_click()

    html = render(view)

    assert html =~ ~r/name=\"brightness\"[^>]*value=\"65\"/
    assert html =~ ~r/name=\"temperature\"[^>]*value=\"3100\"/
  end
end
