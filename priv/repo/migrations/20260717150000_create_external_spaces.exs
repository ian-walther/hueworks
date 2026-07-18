defmodule Hueworks.Repo.Migrations.CreateExternalSpaces do
  use Ecto.Migration

  def change do
    create table(:external_spaces) do
      add(:bridge_id, references(:bridges, on_delete: :delete_all), null: false)
      add(:parent_external_space_id, references(:external_spaces, on_delete: :nilify_all))
      add(:kind, :string, null: false)
      add(:external_id, :string, null: false)
      add(:name, :string, null: false)
      add(:metadata, :map, null: false, default: %{})
      add(:last_seen_at, :utc_datetime_usec, null: false)

      timestamps()
    end

    create(unique_index(:external_spaces, [:bridge_id, :kind, :external_id]))
    create(index(:external_spaces, [:bridge_id, :last_seen_at]))
    create(index(:external_spaces, [:parent_external_space_id]))

    create table(:external_space_mappings) do
      add(
        :external_space_id,
        references(:external_spaces, on_delete: :delete_all),
        null: false
      )

      add(:area_id, references(:areas, on_delete: :delete_all), null: false)

      timestamps()
    end

    create(unique_index(:external_space_mappings, [:external_space_id]))
    create(index(:external_space_mappings, [:area_id]))
  end
end
