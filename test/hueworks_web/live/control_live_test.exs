defmodule HueworksWeb.ControlLiveTest do
  use HueworksWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Hueworks.Repo
  alias Hueworks.Control.DesiredState
  alias Hueworks.Control.State
  alias Hueworks.Schemas.{ActiveScene, Group, GroupLight, Light, Room}
  alias Hueworks.Scenes

  defp insert_room(name \\ "Studio") do
    Repo.insert!(%Room{name: name, metadata: %{}})
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

  test "control page renders room cards with scenes and recursive collapsed controls", %{
    conn: conn
  } do
    room = insert_room("Main Floor")
    bridge = insert_bridge()
    upper_left = insert_light(room, bridge, %{name: "Upper Left"})
    upper_right = insert_light(room, bridge, %{name: "Upper Right"})
    lower_left = insert_light(room, bridge, %{name: "Lower Left"})
    loose = insert_light(room, bridge, %{name: "Loose Lamp"})
    all = insert_group(room, bridge, %{name: "All Cabinet"})
    upper = insert_group(room, bridge, %{name: "Upper Cabinet"})
    {:ok, scene} = Scenes.create_scene(%{name: "Evening", room_id: room.id})

    Enum.each([upper_left, upper_right, lower_left], &insert_group_light(all, &1))
    Enum.each([upper_left, upper_right], &insert_group_light(upper, &1))

    {:ok, view, html} = live(conn, "/control")

    assert html =~ "Control"
    assert has_element?(view, "#control-room-#{room.id}", "Main Floor")

    assert has_element?(
             view,
             "button[phx-click='toggle_scene'][phx-value-id='#{scene.id}']",
             "Activate"
           )

    assert has_element?(view, "#control-room-#{room.id}-group-#{all.id}", "All Cabinet")

    refute has_element?(
             view,
             "#control-room-#{room.id}-group-#{all.id} #control-room-#{room.id}-group-#{upper.id}"
           )

    assert has_element?(
             view,
             "button[phx-click='toggle'][phx-value-type='light'][phx-value-id='#{loose.id}']"
           )

    view
    |> element(
      "button[phx-click='toggle_group_expanded'][phx-value-room_id='#{room.id}'][phx-value-group_id='#{all.id}']"
    )
    |> render_click()

    assert has_element?(
             view,
             "#control-room-#{room.id}-group-#{all.id} #control-room-#{room.id}-group-#{upper.id}"
           )

    refute has_element?(view, "#control-room-#{room.id}-group-#{all.id}-light-#{upper_left.id}")

    view
    |> element(
      "button[phx-click='toggle_group_expanded'][phx-value-room_id='#{room.id}'][phx-value-group_id='#{upper.id}']"
    )
    |> render_click()

    assert has_element?(view, "#control-room-#{room.id}-group-#{upper.id}-light-#{upper_left.id}")
  end

  test "control page activates and deactivates scenes", %{conn: conn} do
    room = insert_room()
    {:ok, scene} = Scenes.create_scene(%{name: "Chill", room_id: room.id})

    {:ok, view, _html} = live(conn, "/control")

    view
    |> element("button[phx-click='toggle_scene'][phx-value-id='#{scene.id}']")
    |> render_click()

    assert has_element?(
             view,
             "button[phx-click='toggle_scene'][phx-value-id='#{scene.id}']",
             "Deactivate"
           )

    assert Repo.get_by!(ActiveScene, room_id: room.id).scene_id == scene.id

    view
    |> element("button[phx-click='toggle_scene'][phx-value-id='#{scene.id}']")
    |> render_click()

    assert has_element?(
             view,
             "button[phx-click='toggle_scene'][phx-value-id='#{scene.id}']",
             "Activate"
           )

    refute Repo.get_by(ActiveScene, room_id: room.id)
  end

  test "light control modal is available only when no scene is active", %{conn: conn} do
    room = insert_room()
    bridge = insert_bridge()

    light =
      insert_light(room, bridge, %{
        name: "Lamp",
        supports_color: true,
        supports_temp: true,
        reported_min_kelvin: 2000,
        reported_max_kelvin: 6500
      })

    {:ok, scene} = Scenes.create_scene(%{name: "Chill", room_id: room.id})

    {:ok, view, _html} = live(conn, "/control")

    assert has_element?(
             view,
             "button[phx-click='open_light_control'][phx-value-id='#{light.id}']",
             "Control"
           )

    view
    |> element("button[phx-click='open_light_control'][phx-value-id='#{light.id}']")
    |> render_click()

    assert has_element?(view, "#control-light-modal-#{light.id}", "Lamp")
    assert has_element?(view, "#control-light-brightness-#{light.id}")
    assert has_element?(view, "#control-light-temp-#{light.id}")
    assert has_element?(view, "#control-light-hue-#{light.id}")
    assert has_element?(view, "#control-light-saturation-#{light.id}")

    _ =
      render_hook(view, "set_brightness", %{
        "type" => "light",
        "id" => Integer.to_string(light.id),
        "level" => "42"
      })

    assert DesiredState.get(:light, light.id) == %{brightness: 42}

    view
    |> element("button[phx-click='close_light_control']")
    |> render_click()

    refute has_element?(view, "#control-light-modal-#{light.id}")

    {:ok, _active} = Hueworks.ActiveScenes.set_active(scene)

    assert eventually(fn ->
             not has_element?(
               view,
               "button[phx-click='open_light_control'][phx-value-id='#{light.id}']",
               "Control"
             )
           end)
  end

  test "group control modal uses member lights and is scene locked", %{conn: conn} do
    room = insert_room()
    bridge = insert_bridge()
    light = insert_light(room, bridge, %{name: "Lamp"})

    group =
      insert_group(room, bridge, %{
        name: "Lamps",
        supports_color: true,
        supports_temp: true,
        reported_min_kelvin: 2000,
        reported_max_kelvin: 6500
      })

    insert_group_light(group, light)
    {:ok, scene} = Scenes.create_scene(%{name: "Chill", room_id: room.id})

    {:ok, view, _html} = live(conn, "/control")

    assert has_element?(
             view,
             "#control-room-#{room.id}-group-#{group.id} button[phx-click='open_group_control'][phx-value-id='#{group.id}']",
             "Control"
           )

    view
    |> element("button[phx-click='open_group_control'][phx-value-id='#{group.id}']")
    |> render_click()

    assert has_element?(view, "#control-group-modal-#{group.id}", "Lamps")
    assert has_element?(view, "#control-group-brightness-#{group.id}")
    assert has_element?(view, "#control-group-temp-#{group.id}")
    assert has_element?(view, "#control-group-hue-#{group.id}")
    assert has_element?(view, "#control-group-saturation-#{group.id}")

    _ =
      render_hook(view, "set_brightness", %{
        "type" => "group",
        "id" => Integer.to_string(group.id),
        "level" => "38"
      })

    assert DesiredState.get(:light, light.id) == %{brightness: 38}

    {:ok, _active} = Hueworks.ActiveScenes.set_active(scene)

    assert eventually(fn ->
             not has_element?(view, "#control-group-modal-#{group.id}") and
               not has_element?(
                 view,
                 "#control-room-#{room.id}-group-#{group.id} button[phx-click='open_group_control'][phx-value-id='#{group.id}']",
                 "Control"
               )
           end)
  end

  test "control page shows enabled groups even when every member light is disabled", %{
    conn: conn
  } do
    room = insert_room()
    bridge = insert_bridge()
    disabled_light = insert_light(room, bridge, %{name: "Hidden Lamp", enabled: false})
    group = insert_group(room, bridge, %{name: "Hidden Lamp Group"})
    insert_group_light(group, disabled_light)

    {:ok, view, _html} = live(conn, "/control")

    assert has_element?(view, "#control-room-#{room.id}-group-#{group.id}", "Hidden Lamp Group")

    refute has_element?(
             view,
             "button[phx-click='toggle_group_expanded'][phx-value-room_id='#{room.id}'][phx-value-group_id='#{group.id}']"
           )

    refute has_element?(
             view,
             "#control-room-#{room.id}-group-#{group.id}-light-#{disabled_light.id}"
           )

    refute has_element?(
             view,
             "button[phx-click='toggle'][phx-value-type='light'][phx-value-id='#{disabled_light.id}']"
           )
  end

  test "control group power label shows ambiguity from member light state", %{conn: conn} do
    room = insert_room()
    bridge = insert_bridge()
    light_a = insert_light(room, bridge, %{name: "Lamp A"})
    light_b = insert_light(room, bridge, %{name: "Lamp B"})
    group = insert_group(room, bridge, %{name: "Lamps"})
    insert_group_light(group, light_a)
    insert_group_light(group, light_b)

    State.put(:light, light_a.id, %{power: :on})
    State.put(:light, light_b.id, %{power: :off})
    State.put(:group, group.id, %{power: :on})

    {:ok, view, _html} = live(conn, "/control")

    assert has_element?(
             view,
             "#control-room-#{room.id}-group-#{group.id} button[phx-click='toggle'][phx-value-type='group'][phx-value-id='#{group.id}'].hw-button-on",
             "..."
           )
  end
end
