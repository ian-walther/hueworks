defmodule Hueworks.ScenesComponentsTest do
  use Hueworks.DataCase, async: false

  alias Hueworks.Repo
  alias Hueworks.Scenes
  alias Hueworks.Control.DesiredState
  alias Hueworks.Schemas.{Bridge, Light, LightState, Room, SceneComponent, SceneComponentLight}

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

  test "replace_scene_components persists components and lights" do
    room = insert_room()
    bridge = insert_bridge()
    light1 = insert_light(room, bridge, %{name: "Lamp"})
    light2 = insert_light(room, bridge, %{name: "Ceiling"})

    {:ok, scene} = Scenes.create_scene(%{name: "Chill", room_id: room.id})

    components = [
      %{name: "Component 1", light_ids: [light1.id]},
      %{name: "Component 2", light_ids: [light2.id]}
    ]

    {:ok, _} = Scenes.replace_scene_components(scene, components)

    scene_components =
      Repo.all(from(sc in SceneComponent, where: sc.scene_id == ^scene.id, preload: [:lights]))

    assert Enum.count(scene_components) == 2
    assert Enum.any?(scene_components, fn sc -> Enum.map(sc.lights, & &1.id) == [light1.id] end)
    assert Enum.any?(scene_components, fn sc -> Enum.map(sc.lights, & &1.id) == [light2.id] end)
  end

  test "replace_scene_components uses the off light state when none specified" do
    room = insert_room()
    bridge = insert_bridge()
    light = insert_light(room, bridge, %{name: "Lamp"})

    {:ok, scene} = Scenes.create_scene(%{name: "Chill", room_id: room.id})

    {:ok, _} =
      Scenes.replace_scene_components(scene, [%{name: "Component 1", light_ids: [light.id]}])

    scene_component =
      Repo.one(
        from(sc in SceneComponent,
          where: sc.scene_id == ^scene.id,
          preload: [:light_state]
        )
      )

    assert scene_component.light_state.type == :off
    assert scene_component.light_state.name == "Off"
  end

  test "replace_scene_components uses selected manual light states without creating new ones" do
    room = insert_room()
    bridge = insert_bridge()
    light = insert_light(room, bridge, %{name: "Lamp"})

    {:ok, state} = Scenes.create_manual_light_state("Soft")
    {:ok, scene} = Scenes.create_scene(%{name: "Chill", room_id: room.id})

    {:ok, _} =
      Scenes.replace_scene_components(scene, [
        %{name: "Component 1", light_ids: [light.id], light_state_id: to_string(state.id)}
      ])

    scene_component =
      Repo.one(
        from(sc in SceneComponent,
          where: sc.scene_id == ^scene.id,
          preload: [:light_state]
        )
      )

    assert scene_component.light_state_id == state.id
    assert Repo.aggregate(from(ls in LightState, where: ls.type == :manual), :count) == 1
  end

  test "replace_scene_components does not delete unused manual light states" do
    room = insert_room()
    bridge = insert_bridge()
    light = insert_light(room, bridge, %{name: "Lamp"})

    {:ok, state} = Scenes.create_manual_light_state("Soft")
    {:ok, scene} = Scenes.create_scene(%{name: "Chill", room_id: room.id})

    {:ok, _} =
      Scenes.replace_scene_components(scene, [
        %{name: "Component 1", light_ids: [light.id], light_state_id: to_string(state.id)}
      ])

    {:ok, _} =
      Scenes.replace_scene_components(scene, [
        %{name: "Component 1", light_ids: [light.id], light_state_id: "off"}
      ])

    assert Repo.get(LightState, state.id)
  end

  test "list_manual_light_states excludes off states" do
    {:ok, _state} = Scenes.create_manual_light_state("Bright")
    _ = Scenes.get_or_create_off_state()

    names = Scenes.list_manual_light_states() |> Enum.map(& &1.name)

    assert "Bright" in names
    refute "Off" in names
  end

  test "replace_scene_components removes old join rows" do
    room = insert_room()
    bridge = insert_bridge()
    light1 = insert_light(room, bridge, %{name: "Lamp"})
    light2 = insert_light(room, bridge, %{name: "Ceiling"})

    {:ok, scene} = Scenes.create_scene(%{name: "Chill", room_id: room.id})

    {:ok, _} =
      Scenes.replace_scene_components(scene, [
        %{name: "Component 1", light_ids: [light1.id, light2.id]}
      ])

    {:ok, _} =
      Scenes.replace_scene_components(scene, [
        %{name: "Component 1", light_ids: [light1.id]}
      ])

    join_count =
      Repo.aggregate(
        from(scl in SceneComponentLight,
          join: sc in SceneComponent,
          on: sc.id == scl.scene_component_id,
          where: sc.scene_id == ^scene.id
        ),
        :count
      )

    assert join_count == 1
  end

  test "activate_scene updates desired state for scene lights" do
    room = insert_room()
    bridge = insert_bridge()
    light1 = insert_light(room, bridge, %{name: "Lamp"})
    light2 = insert_light(room, bridge, %{name: "Ceiling"})

    {:ok, state} =
      Scenes.create_manual_light_state("Soft", %{"brightness" => "40", "temperature" => "3000"})

    {:ok, scene} = Scenes.create_scene(%{name: "Chill", room_id: room.id})

    {:ok, _} =
      Scenes.replace_scene_components(scene, [
        %{name: "Component 1", light_ids: [light1.id, light2.id], light_state_id: to_string(state.id)}
      ])

    {:ok, diff, _updated} = Scenes.activate_scene(scene.id)

    assert diff[{:light, light1.id}][:brightness] == "40"
    assert DesiredState.get(:light, light1.id)[:power] == :on
  end

  test "apply_scene preserves brightness when override is enabled" do
    room = insert_room()
    bridge = insert_bridge()
    light = insert_light(room, bridge, %{name: "Lamp"})

    {:ok, state} =
      Scenes.create_manual_light_state("Soft", %{"brightness" => "80", "temperature" => "3000"})

    {:ok, scene} = Scenes.create_scene(%{name: "Chill", room_id: room.id})

    {:ok, _} =
      Scenes.replace_scene_components(scene, [
        %{name: "Component 1", light_ids: [light.id], light_state_id: to_string(state.id)}
      ])

    _ = Hueworks.Control.State.put(:light, light.id, %{power: :on, brightness: "25", kelvin: "2500"})

    {:ok, _diff, _updated} = Scenes.apply_scene(scene, brightness_override: true)

    desired = DesiredState.get(:light, light.id)
    assert desired[:brightness] == "25"
    assert desired[:kelvin] == "3000"
  end
end
