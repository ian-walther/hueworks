defmodule Hueworks.Repo.Migrations.AddScaleTransitionByBrightnessToAppSettings do
  use Ecto.Migration

  def change do
    alter table(:app_settings) do
      add :scale_transition_by_brightness, :boolean, default: false, null: false
    end
  end
end
