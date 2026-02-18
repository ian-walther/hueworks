defmodule Hueworks.Repo.Migrations.CreateAppSettings do
  use Ecto.Migration

  def change do
    create table(:app_settings) do
      add(:scope, :string, null: false, default: "global")
      add(:latitude, :float)
      add(:longitude, :float)
      add(:timezone, :string)

      timestamps()
    end

    create(unique_index(:app_settings, [:scope]))
  end
end
