defmodule Hueworks.Repo.Migrations.MoveOccupancyToRooms do
  use Ecto.Migration

  def up do
    alter table(:rooms) do
      add(:occupied, :boolean, null: false, default: true)
    end

    alter table(:active_scenes) do
      remove(:occupied)
    end
  end

  def down do
    alter table(:active_scenes) do
      add(:occupied, :boolean, null: false, default: true)
    end

    alter table(:rooms) do
      remove(:occupied)
    end
  end
end
