defmodule Hueworks.Repo.Migrations.AddPowerOverridesToActiveScenes do
  use Ecto.Migration

  def change do
    alter table(:active_scenes) do
      add :power_overrides, :map, default: %{}, null: false
    end
  end
end
