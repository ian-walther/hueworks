defmodule Hueworks.ControlStateActiveSceneTest do
  use Hueworks.DataCase, async: false

  alias Hueworks.ActiveScenes
  alias Hueworks.Control.DesiredState
  alias Hueworks.Control.State
  alias Hueworks.Repo

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

  defp insert_light(room, bridge) do
    Repo.insert!(%Light{
      name: "Lamp",
      source: :hue,
      source_id: Integer.to_string(System.unique_integer([:positive])),
      bridge_id: bridge.id,
      room_id: room.id,
      metadata: %{}
    })
  end

  defp insert_scene(room) do
    Repo.insert!(%Scene{name: "Chill", room_id: room.id, metadata: %{}})
  end

  test "external state divergence clears active scene for the room" do
    room = insert_room()
    bridge = insert_bridge()
    light = insert_light(room, bridge)
    scene = insert_scene(room)

    {:ok, _} = ActiveScenes.set_active(scene)
    active = Repo.get_by!(ActiveScene, room_id: room.id)

    active
    |> Ecto.Changeset.change(pending_until: DateTime.add(DateTime.utc_now(), -5, :second))
    |> Repo.update!()

    _ = DesiredState.put(:light, light.id, %{power: :on, brightness: 50, kelvin: 3000})

    _ = State.put(:light, light.id, %{power: :on, brightness: 40, kelvin: 3000})

    refute Repo.get_by(ActiveScene, room_id: room.id)
  end

  test "external state divergence does not clear active scene while pending" do
    room = insert_room()
    bridge = insert_bridge()
    light = insert_light(room, bridge)
    scene = insert_scene(room)

    {:ok, _} = ActiveScenes.set_active(scene)
    _ = DesiredState.put(:light, light.id, %{power: :on, brightness: 50, kelvin: 3000})

    _ = State.put(:light, light.id, %{power: :on, brightness: 40, kelvin: 3000})

    assert Repo.get_by!(ActiveScene, room_id: room.id).scene_id == scene.id
  end

  test "state updates that match desired do not clear active scene" do
    room = insert_room()
    bridge = insert_bridge()
    light = insert_light(room, bridge)
    scene = insert_scene(room)

    {:ok, _} = ActiveScenes.set_active(scene)
    _ = DesiredState.put(:light, light.id, %{power: :on, brightness: "50", kelvin: "3000"})

    _ = State.put(:light, light.id, %{power: :on, brightness: 50, kelvin: 3000})

    assert Repo.get_by!(ActiveScene, room_id: room.id).scene_id == scene.id
  end
end
