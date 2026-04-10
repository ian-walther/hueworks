defmodule Hueworks.Repo.Migrations.SplitHomeAssistantExportToggles do
  use Ecto.Migration

  def up do
    alter table(:app_settings) do
      add(:ha_export_scenes_enabled, :boolean, default: false, null: false)
      add(:ha_export_room_selects_enabled, :boolean, default: false, null: false)
    end

    execute("""
    UPDATE app_settings
    SET
      ha_export_scenes_enabled = ha_export_enabled,
      ha_export_room_selects_enabled = ha_export_enabled
    """)
  end

  def down do
    alter table(:app_settings) do
      remove(:ha_export_scenes_enabled)
      remove(:ha_export_room_selects_enabled)
    end
  end
end
