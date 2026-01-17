defmodule Hueworks.Repo.Migrations.AddLightTemperatureRange do
  use Ecto.Migration

  def change do
    alter table(:lights) do
      add(:min_kelvin, :integer)
      add(:max_kelvin, :integer)
    end
  end
end
