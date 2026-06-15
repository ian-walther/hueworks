defmodule Hueworks.Repo.Migrations.AddOccupancySources do
  use Ecto.Migration

  def up do
    create table(:occupancy_sources) do
      add(:room_id, references(:rooms, on_delete: :delete_all), null: false)
      add(:name, :string, null: false)
      add(:occupied, :boolean, null: false, default: true)
      add(:metadata, :map, null: false, default: %{})

      timestamps()
    end

    create(index(:occupancy_sources, [:room_id]))
    create(unique_index(:occupancy_sources, [:room_id, :name]))

    alter table(:scene_components) do
      add(:occupancy_source_id, references(:occupancy_sources, on_delete: :nilify_all))
    end

    create(index(:scene_components, [:occupancy_source_id]))

    execute("""
    INSERT INTO occupancy_sources (room_id, name, occupied, metadata, inserted_at, updated_at)
    SELECT id, 'Room Occupancy', occupied, '{}', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP
    FROM rooms
    """)
  end

  def down do
    alter table(:scene_components) do
      remove(:occupancy_source_id)
    end

    drop(table(:occupancy_sources))
  end
end
