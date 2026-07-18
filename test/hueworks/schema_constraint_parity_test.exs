defmodule Hueworks.SchemaConstraintParityTest do
  use Hueworks.DataCase, async: false

  alias Ecto.Adapters.SQL
  alias Hueworks.Repo
  alias Hueworks.Schemas.{ActiveScene, Light, Area, Scene, SceneComponent, SceneComponentLight}

  test "scene component light duplicate is returned as a changeset error" do
    bridge =
      insert_bridge!(%{
        name: "Constraint Bridge",
        type: :hue,
        host: "192.168.1.230",
        credentials: %{"api_key" => "test"}
      })

    area = Repo.insert!(%Area{name: "Constraint Area"})

    light =
      Repo.insert!(%Light{
        name: "Constraint Light",
        display_name: "Constraint Light",
        source: :hue,
        source_id: "constraint-light",
        bridge_id: bridge.id,
        area_id: area.id
      })

    scene = Repo.insert!(%Scene{name: "Constraint Scene", area_id: area.id})

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

  test "one active scene per area is returned as a changeset error" do
    area = Repo.insert!(%Area{name: "Active Constraint Area"})
    scene_a = Repo.insert!(%Scene{name: "First Active Scene", area_id: area.id})
    scene_b = Repo.insert!(%Scene{name: "Second Active Scene", area_id: area.id})

    Repo.insert!(ActiveScene.changeset(%ActiveScene{}, %{area_id: area.id, scene_id: scene_a.id}))

    assert {:error, changeset} =
             %ActiveScene{}
             |> ActiveScene.changeset(%{area_id: area.id, scene_id: scene_b.id})
             |> Repo.insert()

    assert "has already been taken" in errors_on(changeset).area_id
  end

  test "database rejects an area without persisted published identities" do
    assert_raise Exqlite.Error, ~r/areas require persisted published identities/, fn ->
      SQL.query!(
        Repo,
        """
        INSERT INTO areas (name, metadata, inserted_at, updated_at)
        VALUES ('Missing Identity', '{}', '2026-07-17 00:00:00', '2026-07-17 00:00:00')
        """,
        []
      )
    end
  end

  test "database rejects duplicate persisted area identities" do
    Repo.insert!(%Area{
      name: "First Identity",
      ha_device_identifier: "duplicate-device",
      ha_scene_select_identifier: "first-select"
    })

    assert_raise Ecto.ConstraintError, fn ->
      Repo.insert!(%Area{
        name: "Second Identity",
        ha_device_identifier: "duplicate-device",
        ha_scene_select_identifier: "second-select"
      })
    end
  end

  defp errors_on(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {message, opts} ->
      Regex.replace(~r"%{(\w+)}", message, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
  end
end
