defmodule Hueworks.Repo.Migrations.AddBridgeImportHistoryIndex do
  use Ecto.Migration

  def change do
    create index(:bridge_imports, [:bridge_id, :imported_at])
  end
end
