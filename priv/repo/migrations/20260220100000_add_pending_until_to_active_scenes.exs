defmodule Hueworks.Repo.Migrations.AddPendingUntilToActiveScenes do
  use Ecto.Migration

  def change do
    alter table(:active_scenes) do
      add(:pending_until, :utc_datetime_usec)
    end
  end
end
