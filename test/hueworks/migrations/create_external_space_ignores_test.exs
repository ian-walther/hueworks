defmodule Hueworks.Migrations.CreateExternalSpaceIgnoresTest do
  use Hueworks.DataCase, async: false

  alias Ecto.Adapters.SQL
  alias Hueworks.Repo
  alias Hueworks.Repo.Migrations.CreateExternalSpaceIgnores

  unless Code.ensure_loaded?(CreateExternalSpaceIgnores) do
    Code.require_file(
      Path.expand(
        "../../../priv/repo/migrations/20260719120000_create_external_space_ignores.exs",
        __DIR__
      )
    )
  end

  test "backfills only implicit keep-children-separate Floor decisions" do
    suffix = System.unique_integer([:positive])
    spaces = "migration_external_spaces_#{suffix}"
    mappings = "migration_external_space_mappings_#{suffix}"
    ignores = "migration_external_space_ignores_#{suffix}"

    SQL.query!(
      Repo,
      "CREATE TABLE #{spaces} (id INTEGER PRIMARY KEY, kind TEXT, parent_external_space_id INTEGER)",
      []
    )

    SQL.query!(
      Repo,
      "CREATE TABLE #{mappings} (id INTEGER PRIMARY KEY, external_space_id INTEGER)",
      []
    )

    SQL.query!(
      Repo,
      "CREATE TABLE #{ignores} (external_space_id INTEGER, inserted_at TEXT, updated_at TEXT)",
      []
    )

    SQL.query!(
      Repo,
      "INSERT INTO #{spaces} VALUES (1, 'ha_floor', NULL), (2, 'ha_area', 1), (3, 'ha_area', 1)",
      []
    )

    SQL.query!(
      Repo,
      "INSERT INTO #{spaces} VALUES (4, 'ha_floor', NULL), (5, 'ha_area', 4), (6, 'ha_area', 4)",
      []
    )

    SQL.query!(Repo, "INSERT INTO #{spaces} VALUES (7, 'ha_floor', NULL), (8, 'ha_area', 7)", [])
    SQL.query!(Repo, "INSERT INTO #{mappings} VALUES (1, 2), (2, 3), (3, 5), (4, 7), (5, 8)", [])

    sql = CreateExternalSpaceIgnores.implicit_floor_ignores_sql(ignores, spaces, mappings)
    SQL.query!(Repo, sql, [])

    assert SQL.query!(
             Repo,
             "SELECT external_space_id FROM #{ignores} ORDER BY external_space_id",
             []
           ).rows == [[1]]
  end
end
