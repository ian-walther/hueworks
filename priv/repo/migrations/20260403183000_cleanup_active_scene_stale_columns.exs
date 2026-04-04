defmodule Hueworks.Repo.Migrations.CleanupActiveSceneStaleColumns do
  use Ecto.Migration

  def up do
    alter table(:active_scenes) do
      remove(:brightness_override)
      remove(:pending_until)
    end
  end

  def down do
    alter table(:active_scenes) do
      add(:brightness_override, :boolean, default: false, null: false)
      add(:pending_until, :utc_datetime_usec)
    end
  end
end
