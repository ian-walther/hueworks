defmodule Hueworks.Repo.Migrations.CreateGroups do
  use Ecto.Migration

  def change do
    create table(:groups) do
      add :name, :string, null: false
      add :source, :string, null: false
      add :bridge_id, references(:bridges, on_delete: :delete_all), null: false
      add :parent_id, references(:groups, on_delete: :nilify_all)
      add :source_id, :string, null: false
      add :enabled, :boolean, default: true, null: false
      add :metadata, :map, default: %{}, null: false

      timestamps()
    end

    create unique_index(:groups, [:bridge_id, :source_id])
    create index(:groups, [:bridge_id])
    create index(:groups, [:parent_id])
  end
end
