defmodule Hueworks.Repo.Migrations.AddHomekitExportSettings do
  use Ecto.Migration

  def change do
    alter table(:app_settings) do
      add(:homekit_scenes_enabled, :boolean, null: false, default: false)
      add(:homekit_bridge_name, :string)
    end

    alter table(:lights) do
      add(:homekit_export_mode, :string, null: false, default: "none")
    end

    alter table(:groups) do
      add(:homekit_export_mode, :string, null: false, default: "none")
    end
  end
end
