defmodule Hueworks.Migrations.AddPersistedRoomExportIdentitiesTest do
  use Hueworks.DataCase, async: false

  alias Ecto.Adapters.SQL
  alias Hueworks.Repo
  alias Hueworks.Repo.Migrations.AddPersistedRoomExportIdentities
  alias Hueworks.Schemas.Room

  unless Code.ensure_loaded?(AddPersistedRoomExportIdentities) do
    Code.require_file(
      Path.expand(
        "../../../priv/repo/migrations/20260717130000_add_persisted_room_export_identities.exs",
        __DIR__
      )
    )
  end

  test "backfill preserves the exact legacy Home Assistant identities" do
    room = Repo.insert!(%Room{name: "Existing Room"})

    SQL.query!(
      Repo,
      "UPDATE rooms SET ha_device_identifier = NULL, ha_scene_select_identifier = NULL WHERE id = ?",
      [room.id]
    )

    AddPersistedRoomExportIdentities.backfill_identities(Repo, "rooms")

    expected_device_identifier = "hueworks_room_#{room.id}"
    expected_scene_select_identifier = "hueworks_room_scene_select_#{room.id}"

    assert [[^expected_device_identifier, ^expected_scene_select_identifier]] =
             SQL.query!(
               Repo,
               "SELECT ha_device_identifier, ha_scene_select_identifier FROM rooms WHERE id = ?",
               [room.id]
             ).rows
  end

  test "backfill does not replace identities that are already persisted" do
    room =
      Repo.insert!(%Room{
        name: "Persisted Room",
        ha_device_identifier: "custom-device-id",
        ha_scene_select_identifier: "custom-select-id"
      })

    AddPersistedRoomExportIdentities.backfill_identities(Repo, "rooms")

    assert [["custom-device-id", "custom-select-id"]] =
             SQL.query!(
               Repo,
               "SELECT ha_device_identifier, ha_scene_select_identifier FROM rooms WHERE id = ?",
               [room.id]
             ).rows
  end
end
