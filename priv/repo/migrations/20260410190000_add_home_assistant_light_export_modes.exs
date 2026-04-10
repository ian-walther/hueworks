defmodule Hueworks.Repo.Migrations.AddHomeAssistantLightExportModes do
  use Ecto.Migration

  def change do
    alter table(:app_settings) do
      add(:ha_export_lights_enabled, :boolean, default: false, null: false)
    end

    alter table(:lights) do
      add(:ha_export_mode, :string, default: "none", null: false)
    end

    alter table(:groups) do
      add(:ha_export_mode, :string, default: "none", null: false)
    end
  end
end
