defmodule Hueworks.SchemaConstraintParityTest do
  use Hueworks.DataCase, async: false

  alias Hueworks.Repo
  alias Hueworks.Schemas.{ActiveScene, Light, Room, Scene, SceneComponent, SceneComponentLight}

  test "scene component light duplicate is returned as a changeset error" do
    bridge =
      insert_bridge!(%{
        name: "Constraint Bridge",
        type: :hue,
        host: "192.168.1.230",
        credentials: %{"api_key" => "test"}
      })

    room = Repo.insert!(%Room{name: "Constraint Room"})

    light =
      Repo.insert!(%Light{
        name: "Constraint Light",
        display_name: "Constraint Light",
        source: :hue,
        source_id: "constraint-light",
        bridge_id: bridge.id,
        room_id: room.id
      })

    scene = Repo.insert!(%Scene{name: "Constraint Scene", room_id: room.id})

    component =
      Repo.insert!(%SceneComponent{
        scene_id: scene.id,
        embedded_manual_config: %{"power" => "on"}
      })

    attrs = %{
      scene_component_id: component.id,
      light_id: light.id,
      default_power: :default_on
    }

    Repo.insert!(SceneComponentLight.changeset(%SceneComponentLight{}, attrs))

    assert {:error, changeset} =
             %SceneComponentLight{}
             |> SceneComponentLight.changeset(attrs)
             |> Repo.insert()

    assert "has already been taken" in errors_on(changeset).scene_component_id
  end

  test "one active scene per room is returned as a changeset error" do
    room = Repo.insert!(%Room{name: "Active Constraint Room"})
    scene_a = Repo.insert!(%Scene{name: "First Active Scene", room_id: room.id})
    scene_b = Repo.insert!(%Scene{name: "Second Active Scene", room_id: room.id})

    Repo.insert!(ActiveScene.changeset(%ActiveScene{}, %{room_id: room.id, scene_id: scene_a.id}))

    assert {:error, changeset} =
             %ActiveScene{}
             |> ActiveScene.changeset(%{room_id: room.id, scene_id: scene_b.id})
             |> Repo.insert()

    assert "has already been taken" in errors_on(changeset).room_id
  end

  defp errors_on(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {message, opts} ->
      Regex.replace(~r"%{(\w+)}", message, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
  end
end
