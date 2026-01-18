defmodule Hueworks.Repo.Migrations.CreateGroups do
  use Ecto.Migration

  def change do
    create table(:groups) do
      add :name, :string, null: false
      add :source, :string, null: false
      add :bridge_id, references(:bridges, on_delete: :delete_all), null: false
      add :parent_group_id, references(:groups, on_delete: :nilify_all)
      add :canonical_group_id, references(:groups, on_delete: :nilify_all)
      add :source_id, :string, null: false
      add :display_name, :string
      add :supports_color, :boolean, default: false, null: false
      add :supports_temp, :boolean, default: false, null: false
      add :reported_min_kelvin, :integer
      add :reported_max_kelvin, :integer
      add :actual_min_kelvin, :integer
      add :actual_max_kelvin, :integer
      add :enabled, :boolean, default: true, null: false
      add :metadata, :map, default: %{}, null: false

      timestamps()
    end

    create unique_index(:groups, [:bridge_id, :source_id])
    create index(:groups, [:bridge_id])
    create index(:groups, [:parent_group_id])
    create index(:groups, [:canonical_group_id])
  end
end
