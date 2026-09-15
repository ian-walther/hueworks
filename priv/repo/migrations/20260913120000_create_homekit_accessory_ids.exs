defmodule Hueworks.Repo.Migrations.CreateHomekitAccessoryIds do
  use Ecto.Migration

  def change do
    create table(:homekit_accessory_ids) do
      add(:serial_number, :string, null: false)
      add(:aid, :integer, null: false)
      add(:iids, :map, null: false, default: %{})

      timestamps()
    end

    create(unique_index(:homekit_accessory_ids, [:serial_number]))
    create(unique_index(:homekit_accessory_ids, [:aid]))
  end
end
