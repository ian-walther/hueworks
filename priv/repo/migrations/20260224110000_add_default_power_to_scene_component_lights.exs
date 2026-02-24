defmodule Hueworks.Repo.Migrations.AddDefaultPowerToSceneComponentLights do
  use Ecto.Migration

  def change do
    alter table(:scene_component_lights) do
      add(:default_power, :boolean, null: false, default: true)
    end
  end
end
