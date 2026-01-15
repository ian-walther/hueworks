defmodule Hueworks.Repo.Migrations.CreateBridges do
  use Ecto.Migration

  def change do
    create table(:bridges) do
      add :type, :string, null: false
      add :name, :string, null: false
      add :host, :string, null: false
      add :credentials, :map, null: false
      add :enabled, :boolean, default: true, null: false

      timestamps()
    end

    create unique_index(:bridges, [:type, :host])
  end
end
