defmodule Hueworks.Repo.Migrations.AddExtendedMinKelvinToLightsAndGroups do
  use Ecto.Migration

  def change do
    alter table(:lights) do
      add(:extended_min_kelvin, :integer)
    end

    alter table(:groups) do
      add(:extended_min_kelvin, :integer)
    end

    execute(
      "UPDATE lights SET extended_min_kelvin = 2000 WHERE extended_kelvin_range = TRUE",
      "UPDATE lights SET extended_min_kelvin = NULL WHERE extended_min_kelvin = 2000"
    )

    execute(
      "UPDATE groups SET extended_min_kelvin = 2000 WHERE extended_kelvin_range = TRUE",
      "UPDATE groups SET extended_min_kelvin = NULL WHERE extended_min_kelvin = 2000"
    )
  end
end
