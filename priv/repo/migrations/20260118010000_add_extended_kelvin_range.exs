defmodule Hueworks.Repo.Migrations.AddExtendedKelvinRange do
  use Ecto.Migration

  def change do
    alter table(:lights) do
      add(:extended_kelvin_range, :boolean, default: false, null: false)
    end

    alter table(:groups) do
      add(:extended_kelvin_range, :boolean, default: false, null: false)
    end
  end
end
