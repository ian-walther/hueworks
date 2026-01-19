defmodule Hueworks.Repo.Migrations.CreateScenes do
  use Ecto.Migration

  def change do
    create table(:scenes) do
      add(:name, :string, null: false)
      add(:display_name, :string)
      add(:metadata, :map, null: false, default: %{})
      add(:room_id, references(:rooms, on_delete: :delete_all), null: false)

      timestamps()
    end

    create index(:scenes, [:room_id])
  end
end
