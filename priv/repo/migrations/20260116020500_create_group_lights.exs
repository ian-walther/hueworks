defmodule Hueworks.Repo.Migrations.CreateGroupLights do
  use Ecto.Migration

  def change do
    create table(:group_lights) do
      add :group_id, references(:groups, on_delete: :delete_all), null: false
      add :light_id, references(:lights, on_delete: :delete_all), null: false

      timestamps()
    end

    create unique_index(:group_lights, [:group_id, :light_id])
    create index(:group_lights, [:group_id])
    create index(:group_lights, [:light_id])
  end
end
