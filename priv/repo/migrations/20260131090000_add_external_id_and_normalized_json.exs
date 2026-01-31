defmodule Hueworks.Repo.Migrations.AddExternalIdAndNormalizedJson do
  use Ecto.Migration

  def change do
    alter table(:lights) do
      add :external_id, :string
      add :normalized_json, :map
    end

    alter table(:groups) do
      add :external_id, :string
      add :normalized_json, :map
    end

    create index(:lights, [:bridge_id, :external_id])
    create index(:groups, [:bridge_id, :external_id])
  end
end
