defmodule Hueworks.Repo.Migrations.AddApiAccessToAppSettings do
  use Ecto.Migration

  def change do
    alter table(:app_settings) do
      add(:api_enabled, :boolean, null: false, default: false)
      add(:api_token, :string)
    end
  end
end
