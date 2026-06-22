defmodule Hueworks.Repo.Migrations.AddPresenceInputs do
  use Ecto.Migration

  def change do
    create table(:presence_inputs) do
      add(:room_id, references(:rooms, on_delete: :delete_all), null: false)
      add(:name, :text, null: false)
      add(:occupied, :boolean, null: false, default: false)
      add(:metadata, :map, null: false, default: %{})

      timestamps()
    end

    create(index(:presence_inputs, [:room_id]))
  end
end
