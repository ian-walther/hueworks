defmodule Hueworks.AreasSceneBuilderFlowTest do
  use HueworksWeb.ConnCase, async: false

  import Ecto.Query, only: [from: 2]
  import Phoenix.LiveViewTest

  alias Hueworks.Repo
  alias Hueworks.ActiveScenes
  alias Hueworks.Control.DesiredState

  alias Hueworks.Schemas.{
    ActiveScene,
    Group,
    GroupLight,
    Light,
    PresenceInput,
    Area,
    Scene,
    SceneComponent,
    SceneComponentLight
  }

  defp insert_area do
    Repo.insert!(%Area{name: "Studio", metadata: %{}})
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

  defp insert_light(area, bridge, attrs) do
    defaults = %{
      name: "Light",
      source: :hue,
      source_id: Integer.to_string(System.unique_integer([:positive])),
      bridge_id: bridge.id,
      area_id: area.id,
      metadata: %{}
    }

    attrs = Map.merge(defaults, attrs)
    attrs = Map.put(attrs, :display_name, Map.get(attrs, :display_name) || attrs.name)

    Repo.insert!(struct(Light, attrs))
  end

  defp insert_group(area, bridge, attrs) do
    defaults = %{
      name: "Group",
      source: :hue,
      source_id: Integer.to_string(System.unique_integer([:positive])),
      bridge_id: bridge.id,
      area_id: area.id,
      metadata: %{}
    }

    attrs = Map.merge(defaults, attrs)
    attrs = Map.put(attrs, :display_name, Map.get(attrs, :display_name) || attrs.name)

    Repo.insert!(struct(Group, attrs))
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

  test "areas page add-scene action navigates to scene editor", %{conn: conn} do
    area = insert_area()

    {:ok, view, _html} = live(conn, "/areas")

    assert {:error, {:live_redirect, %{to: to}}} =
             view
             |> element("#area-#{area.id} .hw-section-header button[phx-click='open_scene_new']")
             |> render_click()

    assert to == "/areas/#{area.id}/scenes/new"
  end

  test "areas page can create rename and delete presence inputs", %{conn: conn} do
    area = insert_area()

    {:ok, view, _html} = live(conn, "/areas")

    view
    |> form("#area-#{area.id} form[phx-submit='create_presence_input']", %{
      "area_id" => Integer.to_string(area.id),
      "name" => "Desk Presence"
    })
    |> render_submit()

    input = Repo.get_by!(PresenceInput, area_id: area.id, name: "Desk Presence")
    assert input.occupied == false
    assert render(view) =~ ~s(id="presence-input-#{input.id}")
    assert render(view) =~ ~s(value="Desk Presence")
    assert render(view) =~ "Unoccupied"

    view
    |> form("#presence-input-#{input.id} form[phx-submit='update_presence_input']", %{
      "input_id" => Integer.to_string(input.id),
      "name" => "Sitting Area"
    })
    |> render_submit()

    input = Repo.get!(PresenceInput, input.id)
    assert input.name == "Sitting Area"
    assert render(view) =~ ~s(value="Sitting Area")

    assert has_element?(
             view,
             "#presence-input-#{input.id} button[phx-click='delete_presence_input'][data-confirm]"
           )

    view
    |> element("#presence-input-#{input.id} button[phx-click='delete_presence_input']")
    |> render_click()

    refute Repo.get(PresenceInput, input.id)
    refute has_element?(view, "#presence-input-#{input.id}")
  end

  test "areas page edit-scene action navigates to scene editor", %{conn: conn} do
    area = insert_area()
    {:ok, scene} = Hueworks.Scenes.create_scene(%{name: "Chill", area_id: area.id})

    {:ok, view, _html} = live(conn, "/areas")

    assert {:error, {:live_redirect, %{to: to}}} =
             view
             |> element("#area-#{area.id} [phx-click='open_scene_edit']")
             |> render_click()

    assert to == "/areas/#{area.id}/scenes/#{scene.id}/edit"
  end

  test "areas page clone-scene action navigates to a prefilled new scene editor", %{conn: conn} do
    area = insert_area()
    {:ok, scene} = Hueworks.Scenes.create_scene(%{name: "Chill", area_id: area.id})

    {:ok, view, _html} = live(conn, "/areas")

    assert {:error, {:live_redirect, %{to: to}}} =
             view
             |> element("#area-#{area.id} [phx-click='open_scene_clone']")
             |> render_click()

    assert to == "/areas/#{area.id}/scenes/new?clone_scene_id=#{scene.id}"
  end

  test "areas page shows active scenes and toggles activate button to deactivate", %{conn: conn} do
    area = insert_area()
    {:ok, scene} = Hueworks.Scenes.create_scene(%{name: "Chill", area_id: area.id})

    {:ok, view, _html} = live(conn, "/areas")

    assert has_element?(
             view,
             "#area-#{area.id} button[phx-click='activate_scene'][phx-value-id='#{scene.id}']",
             "Activate"
           )

    view
    |> element("#area-#{area.id} button[phx-click='activate_scene'][phx-value-id='#{scene.id}']")
    |> render_click()

    assert has_element?(
             view,
             "#area-#{area.id} button[phx-click='activate_scene'][phx-value-id='#{scene.id}']",
             "Deactivate"
           )

    assert has_element?(view, "#area-#{area.id} .hw-muted", "Active")
    assert Repo.get_by!(ActiveScene, area_id: area.id).scene_id == scene.id
  end

  test "clicking deactivate removes active_scene entry", %{conn: conn} do
    area = insert_area()
    {:ok, scene} = Hueworks.Scenes.create_scene(%{name: "Chill", area_id: area.id})
    {:ok, _} = Hueworks.ActiveScenes.set_active(scene)

    {:ok, view, _html} = live(conn, "/areas")

    assert has_element?(
             view,
             "#area-#{area.id} button[phx-click='activate_scene'][phx-value-id='#{scene.id}']",
             "Deactivate"
           )

    view
    |> element("#area-#{area.id} button[phx-click='activate_scene'][phx-value-id='#{scene.id}']")
    |> render_click()

    assert has_element?(
             view,
             "#area-#{area.id} button[phx-click='activate_scene'][phx-value-id='#{scene.id}']",
             "Activate"
           )

    refute Repo.get_by(ActiveScene, area_id: area.id)
  end

  test "areas page updates active scene status when scene changes live", %{conn: conn} do
    area = insert_area()
    {:ok, scene} = Hueworks.Scenes.create_scene(%{name: "Chill", area_id: area.id})

    {:ok, view, _html} = live(conn, "/areas")

    assert has_element?(
             view,
             "#area-#{area.id} button[phx-click='activate_scene'][phx-value-id='#{scene.id}']",
             "Activate"
           )

    {:ok, _} = Hueworks.ActiveScenes.set_active(scene)

    assert eventually(fn ->
             has_element?(
               view,
               "#area-#{area.id} button[phx-click='activate_scene'][phx-value-id='#{scene.id}']",
               "Deactivate"
             ) and has_element?(view, "#area-#{area.id} .hw-muted", "Active")
           end)

    :ok = Hueworks.ActiveScenes.clear_for_area(area.id)

    assert eventually(fn ->
             has_element?(
               view,
               "#area-#{area.id} button[phx-click='activate_scene'][phx-value-id='#{scene.id}']",
               "Activate"
             ) and not has_element?(view, "#area-#{area.id} .hw-muted", "Active")
           end)
  end

  test "creates a scene with components, lights, and manual light state via the UI", %{conn: conn} do
    area = insert_area()
    bridge = insert_bridge()
    light1 = insert_light(area, bridge, %{name: "Lamp"})
    light2 = insert_light(area, bridge, %{name: "Ceiling"})
    group = insert_group(area, bridge, %{name: "All"})
    insert_group_light(group, light1)
    insert_group_light(group, light2)

    {:ok, state} =
      Hueworks.Scenes.create_manual_light_state("Warm", %{
        "brightness" => "55",
        "temperature" => "3000"
      })

    {:ok, view, _html} = live(conn, "/areas/#{area.id}/scenes/new")

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
    |> form(
      "#scene-component-1-group-#{group.id}-light-#{light1.id} form[phx-change='set_light_default_power']",
      %{
        "component_id" => "1",
        "light_id" => Integer.to_string(light1.id),
        "default_power" => "default_off"
      }
    )
    |> render_change()

    view
    |> form("form[phx-change='update_scene']", %{"name" => "Chill"})
    |> render_change()

    view
    |> element("button[phx-click='save_scene']")
    |> render_click()

    scene =
      Repo.one(from(s in Scene, where: s.area_id == ^area.id and s.name == "Chill"))

    assert_patch(view, "/areas/#{area.id}/scenes/#{scene.id}/edit")

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

    assert default_power_by_light[light1.id] == :default_off
    assert default_power_by_light[light2.id] == :default_on
  end

  test "editing a scene updates components and light state via the UI", %{conn: conn} do
    area = insert_area()
    bridge = insert_bridge()
    light1 = insert_light(area, bridge, %{name: "Lamp"})
    light2 = insert_light(area, bridge, %{name: "Ceiling"})
    group = insert_group(area, bridge, %{name: "All"})
    insert_group_light(group, light1)
    insert_group_light(group, light2)

    {:ok, scene} = Hueworks.Scenes.create_scene(%{name: "Chill", area_id: area.id})

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

    {:ok, view, _html} = live(conn, "/areas/#{area.id}/scenes/#{scene.id}/edit")

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
        from(s in Scene, where: s.area_id == ^area.id and s.display_name == "Chill Updated")
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
    area = insert_area()
    bridge = insert_bridge()
    light = insert_light(area, bridge, %{name: "Lamp"})

    {:ok, view, _html} = live(conn, "/areas/#{area.id}/scenes/new")

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
      Repo.one(from(s in Scene, where: s.area_id == ^area.id and s.name == "Custom Scene"))

    component = Repo.one(from(sc in SceneComponent, where: sc.scene_id == ^scene.id))

    assert_patch(view, "/areas/#{area.id}/scenes/#{scene.id}/edit")
    assert component.light_state_id == nil

    assert component.embedded_manual_config == %{
             "brightness" => 42,
             "mode" => "temperature",
             "temperature" => 2800
           }
  end

  test "saving untouched Custom controls persists the displayed defaults", %{conn: conn} do
    area = insert_area()
    bridge = insert_bridge()
    light = insert_light(area, bridge, %{name: "Lamp", supports_temp: true})

    {:ok, view, _html} = live(conn, "/areas/#{area.id}/scenes/new")

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

    assert has_element?(view, "input[name='brightness'][value='100']")
    assert has_element?(view, "input[name='temperature'][value='3000']")

    view
    |> form("form[phx-change='update_scene']", %{"name" => "Default Custom Scene"})
    |> render_change()

    view
    |> element("button[phx-click='save_scene']")
    |> render_click()

    scene =
      Repo.one(
        from(s in Scene, where: s.area_id == ^area.id and s.name == "Default Custom Scene")
      )

    component = Repo.one(from(sc in SceneComponent, where: sc.scene_id == ^scene.id))

    assert component.embedded_manual_config == %{
             "brightness" => 100,
             "mode" => "temperature",
             "temperature" => 3000
           }
  end

  test "saving untouched Custom Color controls persists the displayed defaults", %{conn: conn} do
    area = insert_area()
    bridge = insert_bridge()
    light = insert_light(area, bridge, %{name: "Lamp", supports_color: true})

    {:ok, view, _html} = live(conn, "/areas/#{area.id}/scenes/new")

    view
    |> form("form[phx-change='select_light'][data-component-id='1']", %{
      "light_id" => Integer.to_string(light.id)
    })
    |> render_change()

    view
    |> form("form[phx-change='select_light_state'][data-component-id='1']", %{
      "component_id" => "1",
      "light_state_id" => "custom_color"
    })
    |> render_change()

    assert has_element?(view, "input[name='brightness'][value='100']")
    assert has_element?(view, "input[name='hue'][value='0']")
    assert has_element?(view, "input[name='saturation'][value='100']")

    view
    |> form("form[phx-change='update_scene']", %{"name" => "Default Custom Color Scene"})
    |> render_change()

    view
    |> element("button[phx-click='save_scene']")
    |> render_click()

    scene =
      Repo.one(
        from(s in Scene,
          where: s.area_id == ^area.id and s.name == "Default Custom Color Scene"
        )
      )

    component = Repo.one(from(sc in SceneComponent, where: sc.scene_id == ^scene.id))

    assert component.embedded_manual_config == %{
             "brightness" => 100,
             "hue" => 0,
             "mode" => "color",
             "saturation" => 100
           }
  end

  test "saved scenes can be activated from the editor and active scene edits refresh desired state",
       %{conn: conn} do
    area = insert_area()
    bridge = insert_bridge()
    light = insert_light(area, bridge, %{name: "Lamp", supports_temp: true})

    {:ok, scene} = Hueworks.Scenes.create_scene(%{name: "Custom Scene", area_id: area.id})

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

    {:ok, view, _html} = live(conn, "/areas/#{area.id}/scenes/#{scene.id}/edit")

    assert has_element?(view, "#scene-toggle-activation", "Activate")

    view
    |> element("#scene-toggle-activation")
    |> render_click()

    assert has_element?(view, "#scene-toggle-activation", "Deactivate")
    assert Hueworks.ActiveScenes.get_for_area(area.id).scene_id == scene.id
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
    area = insert_area()
    bridge = insert_bridge()

    light1 =
      insert_light(area, bridge, %{name: "Lamp 1", supports_color: true, supports_temp: true})

    light2 =
      insert_light(area, bridge, %{name: "Lamp 2", supports_color: true, supports_temp: true})

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

    {:ok, scene} = Hueworks.Scenes.create_scene(%{name: "Color Mix", area_id: area.id})

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

    {:ok, view, _html} = live(conn, "/areas/#{area.id}/scenes/#{scene.id}/edit")

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
    area = insert_area()
    bridge = insert_bridge()
    light1 = insert_light(area, bridge, %{name: "Lamp", supports_color: true})
    light2 = insert_light(area, bridge, %{name: "Ceiling", supports_color: true})

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

    {:ok, scene} = Hueworks.Scenes.create_scene(%{name: "Original", area_id: area.id})

    {:ok, _} =
      Hueworks.Scenes.replace_scene_components(scene, [
        %{
          name: "Component 1",
          light_ids: [light1.id],
          light_state_id: to_string(warm.id),
          light_defaults: %{light1.id => :default_off}
        },
        %{
          name: "Component 2",
          light_ids: [light2.id],
          light_state_id: to_string(blue.id),
          light_defaults: %{light2.id => :default_on}
        }
      ])

    {:ok, view, _html} = live(conn, "/areas/#{area.id}/scenes/new?clone_scene_id=#{scene.id}")

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
      Repo.all(from(s in Scene, where: s.area_id == ^area.id, order_by: [asc: s.id]))

    assert Enum.count(clones) == 2

    cloned_scene = List.last(clones)
    refute cloned_scene.id == scene.id
    assert cloned_scene.name == "Original Copy"
    assert_patch(view, "/areas/#{area.id}/scenes/#{cloned_scene.id}/edit")

    assert scene_component_fingerprint(cloned_scene.id) == scene_component_fingerprint(scene.id)
  end

  test "selecting an existing circadian state saves it on the scene component", %{conn: conn} do
    area = insert_area()
    bridge = insert_bridge()
    light1 = insert_light(area, bridge, %{name: "Lamp"})
    light2 = insert_light(area, bridge, %{name: "Ceiling"})
    group = insert_group(area, bridge, %{name: "All"})
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

    {:ok, view, _html} = live(conn, "/areas/#{area.id}/scenes/new")

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
      Repo.one(from(s in Scene, where: s.area_id == ^area.id and s.name == "Circadian Scene"))

    component =
      Repo.one(
        from(sc in SceneComponent, where: sc.scene_id == ^scene.id, preload: [:light_state])
      )

    assert_patch(view, "/areas/#{area.id}/scenes/#{scene.id}/edit")
    assert component.light_state_id == state.id
    assert component.light_state.type == :circadian
    assert component.light_state.name == "Circadian Day"
  end

  test "saving a scene without a saved light state shows a validation error", %{conn: conn} do
    area = insert_area()
    bridge = insert_bridge()
    light1 = insert_light(area, bridge, %{name: "Lamp"})
    light2 = insert_light(area, bridge, %{name: "Ceiling"})
    group = insert_group(area, bridge, %{name: "All"})
    insert_group_light(group, light1)
    insert_group_light(group, light2)

    {:ok, view, _html} = live(conn, "/areas/#{area.id}/scenes/new")

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

    refute Repo.one(from(s in Scene, where: s.area_id == ^area.id and s.name == "Off Scene"))
  end

  test "saving with unassigned lights shows a validation error banner", %{conn: conn} do
    area = insert_area()
    bridge = insert_bridge()
    _light1 = insert_light(area, bridge, %{name: "Lamp"})
    _light2 = insert_light(area, bridge, %{name: "Ceiling"})

    {:ok, view, _html} = live(conn, "/areas/#{area.id}/scenes/new")

    view
    |> form("form[phx-change='update_scene']", %{"name" => "Blocked"})
    |> render_change()

    view
    |> element("button[phx-click='save_scene']")
    |> render_click()

    assert has_element?(view, ".hw-flash-bar-error", "Assign all lights once before saving.")
  end

  test "disabled area lights are excluded from scene builder options and unassigned counts",
       %{conn: conn} do
    area = insert_area()
    bridge = insert_bridge()
    _enabled = insert_light(area, bridge, %{name: "Lamp", enabled: true})
    _disabled = insert_light(area, bridge, %{name: "Disabled", enabled: false})

    {:ok, view, _html} = live(conn, "/areas/#{area.id}/scenes/new")

    html = render(view)

    assert html =~ "option value=\"\">Select light</option>"
    assert html =~ "Lamp"
    refute html =~ "Disabled"
    assert html =~ "Unassigned lights: 1"
  end

  test "scene editor uses a click save button instead of nested save form", %{conn: conn} do
    area = insert_area()
    bridge = insert_bridge()
    _light1 = insert_light(area, bridge, %{name: "Lamp"})
    _light2 = insert_light(area, bridge, %{name: "Ceiling"})

    {:ok, view, _html} = live(conn, "/areas/#{area.id}/scenes/new")

    refute has_element?(view, "form[phx-submit='save_scene']")
    assert has_element?(view, "button[phx-click='save_scene']")
  end

  test "scene editor persists a custom activation transition", %{conn: conn} do
    area = insert_area()

    scene =
      Repo.insert!(%Scene{
        name: "Evening",
        area_id: area.id,
        metadata: %{}
      })

    {:ok, view, _html} = live(conn, "/areas/#{area.id}/scenes/#{scene.id}/edit")

    assert has_element?(view, "#scene_activation_transition_mode option[value='default']")

    view
    |> form("form[phx-change='update_scene']", %{
      "name" => "Evening",
      "activation_transition_mode" => "custom"
    })
    |> render_change()

    view
    |> form("form[phx-change='update_scene']", %{
      "name" => "Evening",
      "activation_transition_mode" => "custom",
      "activation_transition_value" => "10",
      "activation_transition_unit" => "minutes"
    })
    |> render_change()

    assert has_element?(view, "#scene_activation_transition_value[value='10']")

    assert has_element?(
             view,
             "#scene_activation_transition_unit option[value='minutes'][selected]"
           )

    view
    |> element("button[phx-click='save_scene']")
    |> render_click()

    assert Repo.get!(Scene, scene.id).activation_transition_ms == 600_000
  end

  test "scene editor reloads a persisted custom transition with its mode and unit selected", %{
    conn: conn
  } do
    area = insert_area()

    scene =
      Repo.insert!(%Scene{
        name: "Slow Evening",
        area_id: area.id,
        activation_transition_ms: 600_000,
        metadata: %{}
      })

    {:ok, view, _html} = live(conn, "/areas/#{area.id}/scenes/#{scene.id}/edit")

    assert has_element?(
             view,
             "#scene_activation_transition_mode option[value='custom'][selected]"
           )

    assert has_element?(view, "#scene_activation_transition_value[value='10']")

    assert has_element?(
             view,
             "#scene_activation_transition_unit option[value='minutes'][selected]"
           )
  end

  test "scene editor rejects a blank custom activation transition", %{conn: conn} do
    area = insert_area()
    scene = Repo.insert!(%Scene{name: "Evening", area_id: area.id, metadata: %{}})

    {:ok, view, _html} = live(conn, "/areas/#{area.id}/scenes/#{scene.id}/edit")

    view
    |> form("form[phx-change='update_scene']", %{
      "name" => "Evening",
      "activation_transition_mode" => "custom"
    })
    |> render_change()

    view
    |> form("form[phx-change='update_scene']", %{
      "name" => "Evening",
      "activation_transition_mode" => "custom",
      "activation_transition_value" => "",
      "activation_transition_unit" => "seconds"
    })
    |> render_change()

    view
    |> element("button[phx-click='save_scene']")
    |> render_click()

    assert has_element?(
             view,
             ".hw-flash-bar-error",
             "Custom activation transition must be a positive duration."
           )
  end

  test "scene editor activation publishes a single active scene update", %{conn: conn} do
    area = insert_area()

    scene =
      Repo.insert!(%Scene{
        name: "Evening",
        area_id: area.id,
        metadata: %{}
      })

    Phoenix.PubSub.subscribe(Hueworks.PubSub, ActiveScenes.topic())

    {:ok, view, _html} = live(conn, "/areas/#{area.id}/scenes/#{scene.id}/edit")

    view
    |> element("#scene-toggle-activation", "Activate")
    |> render_click()

    assert_receive {:active_scene_updated, area_id, scene_id}, 100
    assert area_id == area.id
    assert scene_id == scene.id
    refute_receive {:active_scene_updated, ^area_id, ^scene_id}, 50
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
