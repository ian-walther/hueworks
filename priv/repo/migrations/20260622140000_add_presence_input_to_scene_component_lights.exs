defmodule Hueworks.Repo.Migrations.AddPresenceInputToSceneComponentLights do
  use Ecto.Migration

  def change do
    alter table(:scene_component_lights) do
      add(:presence_input_id, references(:presence_inputs, on_delete: :nilify_all))
    end

    create(index(:scene_component_lights, [:presence_input_id]))
  end
end
