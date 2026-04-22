defmodule Hueworks.Migrations.AddEmbeddedManualConfigToSceneComponentsTest do
  use Hueworks.DataCase, async: false

  Code.require_file(
    Path.expand("../../../priv/repo/migrations/20260421110000_add_embedded_manual_config_to_scene_components.exs", __DIR__)
  )

  alias Ecto.Adapters.SQL
  alias Hueworks.Repo
  alias Hueworks.Repo.Migrations.AddEmbeddedManualConfigToSceneComponents
  alias Hueworks.Schemas.{LightState, Room, Scene}

  test "rebuild_scene_components preserves existing scene component light rows" do
    room = Repo.insert!(%Room{name: "Migration Room"})
    scene = Repo.insert!(%Scene{name: "Migration Scene", room_id: room.id})
    light_state = Repo.insert!(%LightState{name: "Migration State", type: :manual, config: %{}})

    suffix = System.unique_integer([:positive])
    component_table = "migration_scene_components_#{suffix}"
    join_table = "migration_scene_component_lights_#{suffix}"

    SQL.query!(
      Repo,
      """
      CREATE TABLE #{component_table} (
        id INTEGER PRIMARY KEY,
        name TEXT,
        metadata TEXT NOT NULL DEFAULT '{}',
        scene_id INTEGER NOT NULL,
        light_state_id INTEGER NOT NULL,
        inserted_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
      """,
      []
    )

    SQL.query!(
      Repo,
      """
      CREATE TABLE #{join_table} (
        id INTEGER PRIMARY KEY,
        scene_component_id INTEGER NOT NULL,
        light_id INTEGER NOT NULL,
        inserted_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        FOREIGN KEY (scene_component_id) REFERENCES #{component_table}(id) ON DELETE CASCADE
      )
      """,
      []
    )

    SQL.query!(
      Repo,
      """
      INSERT INTO #{component_table}
        (id, name, metadata, scene_id, light_state_id, inserted_at, updated_at)
      VALUES
        (1, 'Component 1', '{}', ?, ?, '2026-04-21 00:00:00', '2026-04-21 00:00:00')
      """,
      [scene.id, light_state.id]
    )

    SQL.query!(
      Repo,
      """
      INSERT INTO #{join_table}
        (id, scene_component_id, light_id, inserted_at, updated_at)
      VALUES
        (1, 1, 30, '2026-04-21 00:00:00', '2026-04-21 00:00:00')
      """,
      []
    )

    AddEmbeddedManualConfigToSceneComponents.rebuild_scene_components(Repo, component_table, join_table)

    assert [[1]] =
             SQL.query!(Repo, "SELECT COUNT(*) FROM #{component_table}", []).rows

    assert [[1]] =
             SQL.query!(Repo, "SELECT COUNT(*) FROM #{join_table}", []).rows
  end
end
