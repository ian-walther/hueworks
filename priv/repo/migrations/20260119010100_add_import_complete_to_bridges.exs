defmodule Hueworks.Repo.Migrations.AddImportCompleteToBridges do
  use Ecto.Migration

  def change do
    alter table(:bridges) do
      add :import_complete, :boolean, default: false, null: false
    end
  end
end
