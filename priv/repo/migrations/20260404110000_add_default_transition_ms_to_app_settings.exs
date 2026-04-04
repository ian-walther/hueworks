defmodule Hueworks.Repo.Migrations.AddDefaultTransitionMsToAppSettings do
  use Ecto.Migration

  def change do
    alter table(:app_settings) do
      add(:default_transition_ms, :integer, default: 0, null: false)
    end
  end
end
