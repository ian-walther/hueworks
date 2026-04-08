defmodule Hueworks.Repo.Migrations.AddHomeAssistantExportSettingsToAppSettings do
  use Ecto.Migration

  def change do
    alter table(:app_settings) do
      add(:ha_export_enabled, :boolean, default: false, null: false)
      add(:ha_export_mqtt_host, :string)
      add(:ha_export_mqtt_port, :integer, default: 1883)
      add(:ha_export_mqtt_username, :string)
      add(:ha_export_mqtt_password, :string)
      add(:ha_export_discovery_prefix, :string, default: "homeassistant")
    end
  end
end
