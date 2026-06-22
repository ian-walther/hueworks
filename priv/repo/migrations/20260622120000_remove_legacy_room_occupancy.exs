defmodule Hueworks.Repo.Migrations.RemoveLegacyRoomOccupancy do
  use Ecto.Migration

  def up do
    execute("""
    UPDATE scene_component_lights
    SET default_power = 'default_on'
    WHERE default_power = 'follow_occupancy'
    """)

    alter table(:scene_components) do
      remove(:occupancy_source_id)
    end

    drop(table(:occupancy_sources))

    alter table(:rooms) do
      remove(:occupied)
    end
  end

  def down do
    alter table(:rooms) do
      add(:occupied, :boolean, null: false, default: true)
    end

    create table(:occupancy_sources) do
      add(:room_id, references(:rooms, on_delete: :delete_all), null: false)
      add(:name, :text, null: false)
      add(:occupied, :boolean, null: false, default: true)
      add(:metadata, :map, null: false, default: %{})

      timestamps()
    end

    create(index(:occupancy_sources, [:room_id]))

    alter table(:scene_components) do
      add(:occupancy_source_id, references(:occupancy_sources, on_delete: :nilify_all))
    end

    create(index(:scene_components, [:occupancy_source_id]))
  end
end
