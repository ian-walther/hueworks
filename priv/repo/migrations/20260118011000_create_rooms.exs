defmodule Hueworks.Repo.Migrations.CreateRooms do
  use Ecto.Migration

  def change do
    create table(:rooms) do
      add(:name, :string, null: false)
      add(:display_name, :string)
      add(:metadata, :map, null: false, default: %{})

      timestamps()
    end

    alter table(:lights) do
      add(:room_id, references(:rooms, on_delete: :nilify_all))
    end

    alter table(:groups) do
      add(:room_id, references(:rooms, on_delete: :nilify_all))
    end

    create index(:lights, [:room_id])
    create index(:groups, [:room_id])
  end
end
