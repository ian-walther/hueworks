defmodule Hueworks.Repo.Migrations.AddPersistedRoomExportIdentities do
  use Ecto.Migration

  def up do
    alter table(:rooms) do
      add(:ha_device_identifier, :string)
      add(:ha_scene_select_identifier, :string)
    end

    flush()
    backfill_identities(repo(), "rooms")

    create(unique_index(:rooms, [:ha_device_identifier]))
    create(unique_index(:rooms, [:ha_scene_select_identifier]))
  end

  def down do
    drop_if_exists(unique_index(:rooms, [:ha_scene_select_identifier]))
    drop_if_exists(unique_index(:rooms, [:ha_device_identifier]))

    alter table(:rooms) do
      remove(:ha_scene_select_identifier)
      remove(:ha_device_identifier)
    end
  end

  def backfill_identities(repo, table) when is_binary(table) do
    repo.query!(
      """
      UPDATE #{table}
      SET ha_device_identifier = 'hueworks_room_' || id
      WHERE ha_device_identifier IS NULL OR ha_device_identifier = ''
      """,
      []
    )

    repo.query!(
      """
      UPDATE #{table}
      SET ha_scene_select_identifier = 'hueworks_room_scene_select_' || id
      WHERE ha_scene_select_identifier IS NULL OR ha_scene_select_identifier = ''
      """,
      []
    )

    :ok
  end
end
