defmodule Hueworks.Repo.Migrations.CreateBridgeImports do
  use Ecto.Migration

  def change do
    create table(:bridge_imports) do
      add :bridge_id, references(:bridges, on_delete: :delete_all), null: false
      add :raw_blob, :map, null: false
      add :normalized_blob, :map
      add :status, :string, null: false, default: "fetched"
      add :imported_at, :utc_datetime, null: false

      timestamps()
    end

    create index(:bridge_imports, [:bridge_id])
  end
end
