defmodule Hueworks.Repo.Migrations.CreateExternalSpaceIgnores do
  use Ecto.Migration

  def up do
    create table(:external_space_ignores) do
      add(
        :external_space_id,
        references(:external_spaces, on_delete: :delete_all),
        null: false
      )

      timestamps()
    end

    create(unique_index(:external_space_ignores, [:external_space_id]))

    # A Floor with every child mapped represented the old "keep Areas separate" decision.
    execute(implicit_floor_ignores_sql())
  end

  def down do
    drop(table(:external_space_ignores))
  end

  def implicit_floor_ignores_sql(
        ignores_table \\ "external_space_ignores",
        spaces_table \\ "external_spaces",
        mappings_table \\ "external_space_mappings"
      ) do
    """
    INSERT INTO #{ignores_table}
      (external_space_id, inserted_at, updated_at)
    SELECT floor.id, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP
    FROM #{spaces_table} AS floor
    WHERE floor.kind = 'ha_floor'
      AND NOT EXISTS (
        SELECT 1
        FROM #{mappings_table} AS floor_mapping
        WHERE floor_mapping.external_space_id = floor.id
      )
      AND EXISTS (
        SELECT 1
        FROM #{spaces_table} AS child
        WHERE child.parent_external_space_id = floor.id
      )
      AND NOT EXISTS (
        SELECT 1
        FROM #{spaces_table} AS child
        LEFT JOIN #{mappings_table} AS child_mapping
          ON child_mapping.external_space_id = child.id
        WHERE child.parent_external_space_id = floor.id
          AND child_mapping.id IS NULL
      )
    """
  end
end
