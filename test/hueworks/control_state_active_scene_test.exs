defmodule Hueworks.ControlStateActiveSceneTest do
  use Hueworks.DataCase, async: false

  alias Hueworks.ActiveScenes
  alias Hueworks.Control.DesiredState
  alias Hueworks.Control.State
  alias Hueworks.Repo
  alias Hueworks.Scenes

  alias Hueworks.Schemas.{
    ActiveScene,
    Bridge,
    Light,
    Room,
    Scene
  }

  defp insert_room do
    Repo.insert!(%Room{name: "Studio", metadata: %{}})
  end

  defp insert_bridge(type \\ :hue) do
    Repo.insert!(%Bridge{
      type: type,
      name: "Hue Bridge",
      host: "10.0.0.230",
      credentials: %{"api_key" => "key"},
      import_complete: false,
      enabled: true
    })
  end

  defp insert_light(room, bridge, attrs \\ %{}) do
    defaults = %{
      name: "Lamp",
      source: :hue,
      source_id: Integer.to_string(System.unique_integer([:positive])),
      bridge_id: bridge.id,
      room_id: room.id,
      metadata: %{}
    }

    Repo.insert!(struct(Light, Map.merge(defaults, attrs)))
  end

  defp insert_scene(room) do
    Repo.insert!(%Scene{name: "Chill", room_id: room.id, metadata: %{}})
  end

  test "external state divergence does not clear active scene for the room" do
    room = insert_room()
    bridge = insert_bridge()
    light = insert_light(room, bridge)
    scene = insert_scene(room)

    {:ok, _} = ActiveScenes.set_active(scene)
    _ = DesiredState.put(:light, light.id, %{power: :on, brightness: 50, kelvin: 3000})

    _ = State.put(:light, light.id, %{power: :on, brightness: 40, kelvin: 3000})

    assert %ActiveScene{scene_id: scene_id} = Repo.get_by(ActiveScene, room_id: room.id)
    assert scene_id == scene.id
  end

  test "power-only state changes do not clear active scene" do
    room = insert_room()
    bridge = insert_bridge()
    light = insert_light(room, bridge)
    scene = insert_scene(room)

    {:ok, _} = ActiveScenes.set_active(scene)
    _ = DesiredState.put(:light, light.id, %{power: :on, brightness: 46, kelvin: 3000})

    _ = State.put(:light, light.id, %{power: :off, brightness: 46, kelvin: 3000})

    assert %ActiveScene{scene_id: scene_id} = Repo.get_by(ActiveScene, room_id: room.id)
    assert scene_id == scene.id
  end

  test "bootstrap state refresh does not clear active scene" do
    room = insert_room()
    bridge = insert_bridge()
    light = insert_light(room, bridge)
    scene = insert_scene(room)

    {:ok, _} = ActiveScenes.set_active(scene)
    _ = DesiredState.put(:light, light.id, %{power: :on, brightness: 24, kelvin: 3000})

    _ =
      State.put(:light, light.id, %{power: :on, brightness: 31, kelvin: 3000}, source: :bootstrap)

    assert %ActiveScene{scene_id: scene_id} = Repo.get_by(ActiveScene, room_id: room.id)
    assert scene_id == scene.id
  end

  test "manual scene reapply keeps the active scene row after later physical updates land" do
    room = insert_room()
    bridge = insert_bridge()
    light = insert_light(room, bridge, %{supports_temp: true})
    scene = insert_scene(room)

    {:ok, _} = ActiveScenes.set_active(scene)

    assert {:ok, _diff, _updated} =
             Scenes.recompute_active_scene_lights(room.id, [light.id], power_override: :off)

    _ = DesiredState.put(:light, light.id, %{power: :off})
    _ = State.put(:light, light.id, %{power: :on, brightness: 50, kelvin: 3000})

    assert %ActiveScene{scene_id: scene_id} = Repo.get_by(ActiveScene, room_id: room.id)
    assert scene_id == scene.id
  end
end
