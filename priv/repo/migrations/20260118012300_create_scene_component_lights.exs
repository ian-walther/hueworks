defmodule Hueworks.Repo.Migrations.CreateSceneComponentLights do
  use Ecto.Migration

  def change do
    create table(:scene_component_lights) do
      add(:scene_component_id, references(:scene_components, on_delete: :delete_all), null: false)
      add(:light_id, references(:lights, on_delete: :delete_all), null: false)

      timestamps()
    end

    create index(:scene_component_lights, [:scene_component_id])
    create index(:scene_component_lights, [:light_id])
    create unique_index(:scene_component_lights, [:scene_component_id, :light_id])
  end
end
