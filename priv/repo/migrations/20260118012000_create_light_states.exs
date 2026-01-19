defmodule Hueworks.Repo.Migrations.CreateLightStates do
  use Ecto.Migration

  def change do
    create table(:light_states) do
      add(:name, :string, null: false)
      add(:type, :string, null: false)
      add(:config, :map, null: false, default: %{})

      timestamps()
    end
  end
end
