defmodule Hueworks.Repo.Migrations.CreateSceneComponents do
  use Ecto.Migration

  def change do
    create table(:scene_components) do
      add(:name, :string)
      add(:metadata, :map, null: false, default: %{})
      add(:scene_id, references(:scenes, on_delete: :delete_all), null: false)
      add(:light_state_id, references(:light_states, on_delete: :restrict), null: false)

      timestamps()
    end

    create index(:scene_components, [:scene_id])
    create index(:scene_components, [:light_state_id])
  end
end
