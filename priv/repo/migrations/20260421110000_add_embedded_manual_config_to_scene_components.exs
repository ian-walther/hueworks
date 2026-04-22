defmodule Hueworks.Repo.Migrations.AddEmbeddedManualConfigToSceneComponents do
  use Ecto.Migration

  alias Ecto.Adapters.SQL

  def up do
    rebuild_scene_components(repo(), "scene_components", "scene_component_lights")
  end

  def down do
    rollback_scene_components(repo(), "scene_components", "scene_component_lights")
  end

  def rebuild_scene_components(repo, component_table, join_table) do
    SQL.query!(repo, "PRAGMA foreign_keys=OFF", [])
    backup_join_rows(repo, join_table)

    SQL.query!(
      repo,
      """
      CREATE TABLE #{component_table}_new (
        id INTEGER PRIMARY KEY,
        name TEXT,
        metadata TEXT NOT NULL DEFAULT '{}',
        embedded_manual_config TEXT,
        scene_id INTEGER NOT NULL,
        light_state_id INTEGER,
        inserted_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        FOREIGN KEY (scene_id) REFERENCES scenes(id) ON DELETE CASCADE,
        FOREIGN KEY (light_state_id) REFERENCES light_states(id) ON DELETE RESTRICT
      )
      """,
      []
    )

    SQL.query!(
      repo,
      """
      INSERT INTO #{component_table}_new
        (id, name, metadata, embedded_manual_config, scene_id, light_state_id, inserted_at, updated_at)
      SELECT
        id, name, metadata, NULL, scene_id, light_state_id, inserted_at, updated_at
      FROM #{component_table}
      """,
      []
    )

    SQL.query!(repo, "DROP TABLE #{component_table}", [])
    SQL.query!(repo, "ALTER TABLE #{component_table}_new RENAME TO #{component_table}", [])
    restore_join_rows(repo, join_table)
    SQL.query!(repo, "CREATE INDEX #{component_table}_scene_id_index ON #{component_table} (scene_id)", [])

    SQL.query!(
      repo,
      "CREATE INDEX #{component_table}_light_state_id_index ON #{component_table} (light_state_id)",
      []
    )

    SQL.query!(repo, "PRAGMA foreign_keys=ON", [])
  end

  def rollback_scene_components(repo, component_table, join_table) do
    SQL.query!(repo, "PRAGMA foreign_keys=OFF", [])
    backup_join_rows(repo, join_table)

    SQL.query!(
      repo,
      """
      CREATE TABLE #{component_table}_old (
        id INTEGER PRIMARY KEY,
        name TEXT,
        metadata TEXT NOT NULL DEFAULT '{}',
        scene_id INTEGER NOT NULL,
        light_state_id INTEGER NOT NULL,
        inserted_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        FOREIGN KEY (scene_id) REFERENCES scenes(id) ON DELETE CASCADE,
        FOREIGN KEY (light_state_id) REFERENCES light_states(id) ON DELETE RESTRICT
      )
      """,
      []
    )

    SQL.query!(
      repo,
      """
      INSERT INTO #{component_table}_old
        (id, name, metadata, scene_id, light_state_id, inserted_at, updated_at)
      SELECT
        id, name, metadata, scene_id, light_state_id, inserted_at, updated_at
      FROM #{component_table}
      WHERE light_state_id IS NOT NULL
      """,
      []
    )

    SQL.query!(repo, "DROP TABLE #{component_table}", [])
    SQL.query!(repo, "ALTER TABLE #{component_table}_old RENAME TO #{component_table}", [])
    restore_join_rows(repo, join_table)
    SQL.query!(repo, "CREATE INDEX #{component_table}_scene_id_index ON #{component_table} (scene_id)", [])

    SQL.query!(
      repo,
      "CREATE INDEX #{component_table}_light_state_id_index ON #{component_table} (light_state_id)",
      []
    )

    SQL.query!(repo, "PRAGMA foreign_keys=ON", [])
  end

  defp backup_join_rows(repo, join_table) do
    SQL.query!(repo, "DROP TABLE IF EXISTS #{join_table}_backup", [])
    SQL.query!(repo, "CREATE TABLE #{join_table}_backup AS SELECT * FROM #{join_table}", [])
  end

  defp restore_join_rows(repo, join_table) do
    SQL.query!(repo, "DELETE FROM #{join_table}", [])
    SQL.query!(repo, "INSERT INTO #{join_table} SELECT * FROM #{join_table}_backup", [])
    SQL.query!(repo, "DROP TABLE #{join_table}_backup", [])
  end
end
