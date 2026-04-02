defmodule Hueworks.Repo.Migrations.CreateExternalScenes do
  use Ecto.Migration

  def change do
    create table(:external_scenes) do
      add :bridge_id, references(:bridges, on_delete: :delete_all), null: false
      add :source, :string, null: false
      add :source_id, :string, null: false
      add :name, :string, null: false
      add :display_name, :string
      add :enabled, :boolean, null: false, default: true
      add :metadata, :map, null: false, default: %{}

      timestamps()
    end

    create unique_index(:external_scenes, [:bridge_id, :source, :source_id])

    create table(:external_scene_mappings) do
      add :external_scene_id, references(:external_scenes, on_delete: :delete_all), null: false
      add :scene_id, references(:scenes, on_delete: :delete_all)
      add :enabled, :boolean, null: false, default: true
      add :metadata, :map, null: false, default: %{}

      timestamps()
    end

    create unique_index(:external_scene_mappings, [:external_scene_id])
  end
end
