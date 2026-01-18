defmodule Hueworks.Repo.Migrations.AddLightTemperatureRange do
  use Ecto.Migration

  def change do
    alter table(:lights) do
      add(:reported_min_kelvin, :integer)
      add(:reported_max_kelvin, :integer)
      add(:actual_min_kelvin, :integer)
      add(:actual_max_kelvin, :integer)
    end
  end
end
