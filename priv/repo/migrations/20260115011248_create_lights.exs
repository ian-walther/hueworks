defmodule Hueworks.Repo.Migrations.CreateLights do
  use Ecto.Migration

  def change do
    create table(:lights) do
      add :name, :string, null: false
      add :source, :string, null: false
      add :bridge_id, references(:bridges, on_delete: :delete_all), null: false
      add :canonical_light_id, references(:lights, on_delete: :nilify_all)
      add :source_id, :string, null: false
      add :supports_color, :boolean, default: false, null: false
      add :supports_temp, :boolean, default: false, null: false
      add :enabled, :boolean, default: true, null: false
      add :metadata, :map, default: %{}, null: false

      timestamps()
    end

    create unique_index(:lights, [:bridge_id, :source_id])
    create index(:lights, [:bridge_id])
    create index(:lights, [:canonical_light_id])
  end
end
