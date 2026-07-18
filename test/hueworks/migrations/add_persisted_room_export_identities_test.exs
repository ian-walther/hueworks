defmodule Hueworks.Migrations.AddPersistedRoomExportIdentitiesTest do
  use Hueworks.DataCase, async: false

  alias Ecto.Adapters.SQL
  alias Hueworks.Repo
  alias Hueworks.Repo.Migrations.AddPersistedRoomExportIdentities

  unless Code.ensure_loaded?(AddPersistedRoomExportIdentities) do
    Code.require_file(
      Path.expand(
        "../../../priv/repo/migrations/20260717130000_add_persisted_room_export_identities.exs",
        __DIR__
      )
    )
  end

  test "backfill preserves the exact legacy Home Assistant identities" do
    table = identity_table!()

    SQL.query!(
      Repo,
      "INSERT INTO #{table} (id, ha_device_identifier, ha_scene_select_identifier) VALUES (42, NULL, NULL)",
      []
    )

    AddPersistedRoomExportIdentities.backfill_identities(Repo, table)

    expected_device_identifier = "hueworks_room_42"
    expected_scene_select_identifier = "hueworks_room_scene_select_42"

    assert [[^expected_device_identifier, ^expected_scene_select_identifier]] =
             SQL.query!(
               Repo,
               "SELECT ha_device_identifier, ha_scene_select_identifier FROM #{table} WHERE id = 42",
               []
             ).rows
  end

  test "backfill does not replace identities that are already persisted" do
    table = identity_table!()

    SQL.query!(
      Repo,
      "INSERT INTO #{table} (id, ha_device_identifier, ha_scene_select_identifier) VALUES (42, 'custom-device-id', 'custom-select-id')",
      []
    )

    AddPersistedRoomExportIdentities.backfill_identities(Repo, table)

    assert [["custom-device-id", "custom-select-id"]] =
             SQL.query!(
               Repo,
               "SELECT ha_device_identifier, ha_scene_select_identifier FROM #{table} WHERE id = 42",
               []
             ).rows
  end

  defp identity_table! do
    table = "migration_room_identities_#{System.unique_integer([:positive])}"

    SQL.query!(
      Repo,
      "CREATE TABLE #{table} (id INTEGER PRIMARY KEY, ha_device_identifier TEXT, ha_scene_select_identifier TEXT)",
      []
    )

    table
  end
end
