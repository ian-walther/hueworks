defmodule Hueworks.Repo.Migrations.UpdateSceneComponentLightPowerAndActiveSceneOccupancy do
  use Ecto.Migration

  def up do
    alter table(:scene_component_lights) do
      remove(:default_power)
      add(:default_power, :string, null: false, default: "force_on")
    end

    alter table(:active_scenes) do
      add(:occupied, :boolean, null: false, default: true)
    end
  end

  def down do
    alter table(:active_scenes) do
      remove(:occupied)
    end

    alter table(:scene_component_lights) do
      remove(:default_power)
      add(:default_power, :boolean, null: false, default: true)
    end
  end
end
