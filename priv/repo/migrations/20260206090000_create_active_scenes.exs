defmodule Hueworks.Repo.Migrations.CreateActiveScenes do
  use Ecto.Migration

  def change do
    create table(:active_scenes) do
      add :room_id, references(:rooms, on_delete: :delete_all), null: false
      add :scene_id, references(:scenes, on_delete: :delete_all), null: false
      add :brightness_override, :boolean, default: false, null: false
      add :last_applied_at, :utc_datetime_usec

      timestamps()
    end

    create unique_index(:active_scenes, [:room_id])
  end
end
