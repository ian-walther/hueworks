defmodule Hueworks.Repo.Migrations.AddExternalIdToBridges do
  use Ecto.Migration

  def change do
    alter table(:bridges) do
      add :external_id, :string
    end

    create unique_index(:bridges, [:type, :external_id])
  end
end
