defmodule Hueworks.BackupRestoreDbTest do
  use ExUnit.Case, async: false

  alias Exqlite.Sqlite3
  alias Hueworks.DatabaseMaintenance

  setup do
    tmp_dir =
      Path.join(
        System.tmp_dir!(),
        "hueworks-db-maintenance-#{System.unique_integer([:positive])}"
      )

    File.mkdir_p!(tmp_dir)

    on_exit(fn -> File.rm_rf!(tmp_dir) end)

    {:ok, tmp_dir: tmp_dir}
  end

  test "backup leaves source intact and includes committed WAL data", %{tmp_dir: tmp_dir} do
    db_path = Path.join(tmp_dir, "hueworks.db")
    backup_path = Path.join(tmp_dir, "hueworks_backup.db")

    {:ok, conn} = Sqlite3.open(db_path)

    try do
      :ok = Sqlite3.execute(conn, "PRAGMA journal_mode = WAL")
      :ok = Sqlite3.execute(conn, "PRAGMA wal_autocheckpoint = 0")
      :ok = Sqlite3.execute(conn, "CREATE TABLE lights (name TEXT)")
      :ok = Sqlite3.execute(conn, "INSERT INTO lights VALUES ('source')")
      :ok = Sqlite3.execute(conn, "INSERT INTO lights VALUES ('wal')")

      assert File.exists?(db_path <> "-wal")

      assert {:ok, ^backup_path} =
               DatabaseMaintenance.backup(db_path, backup_path: backup_path)

      assert File.exists?(db_path)
      assert File.exists?(backup_path)
      assert table_values(db_path, "lights") == ["source", "wal"]
      assert table_values(backup_path, "lights") == ["source", "wal"]
    after
      Sqlite3.close(conn)
    end
  end

  test "restore rejects corrupt input without touching the current database", %{tmp_dir: tmp_dir} do
    db_path = Path.join(tmp_dir, "hueworks.db")
    backup_path = Path.join(tmp_dir, "hueworks_20260710T120000.db")

    create_values_db!(db_path, "lights", ["current"])
    File.write!(backup_path, "not a sqlite database")

    assert {:error, {:integrity_check_failed, _reason}} =
             DatabaseMaintenance.restore(db_path,
               backup_path: backup_path,
               force: true,
               active_check: fn -> false end
             )

    assert table_values(db_path, "lights") == ["current"]
  end

  test "restore requires force and refuses to run when the app is active", %{tmp_dir: tmp_dir} do
    db_path = Path.join(tmp_dir, "hueworks.db")
    backup_path = Path.join(tmp_dir, "hueworks_20260710T120000.db")

    create_values_db!(db_path, "lights", ["current"])
    create_values_db!(backup_path, "lights", ["backup"])

    assert {:error, :force_required} =
             DatabaseMaintenance.restore(db_path,
               backup_path: backup_path,
               active_check: fn -> false end
             )

    assert {:error, :application_running} =
             DatabaseMaintenance.restore(db_path,
               backup_path: backup_path,
               force: true,
               active_check: fn -> true end
             )

    assert table_values(db_path, "lights") == ["current"]
  end

  test "successful restore keeps backup and creates a recovery snapshot", %{tmp_dir: tmp_dir} do
    db_path = Path.join(tmp_dir, "hueworks.db")
    backup_path = Path.join(tmp_dir, "hueworks_20260710T120000.db")

    create_values_db!(db_path, "lights", ["current"])
    create_values_db!(backup_path, "lights", ["backup"])

    assert {:ok, result} =
             DatabaseMaintenance.restore(db_path,
               backup_path: backup_path,
               force: true,
               timestamp: "20260710T121500",
               active_check: fn -> false end
             )

    assert result.restored_path == db_path
    assert result.backup_path == backup_path
    assert result.recovery_path == Path.join(tmp_dir, "hueworks_pre_restore_20260710T121500.db")

    assert File.exists?(backup_path)
    assert File.exists?(result.recovery_path)
    assert table_values(db_path, "lights") == ["backup"]
    assert table_values(result.recovery_path, "lights") == ["current"]
  end

  test "prunes only older backups from the requested retention set", %{tmp_dir: tmp_dir} do
    automated =
      for timestamp <- ~w(20260710T120000 20260711T120000 20260712T120000) do
        path = Path.join(tmp_dir, "hueworks_pre_migration_#{timestamp}.db")
        File.write!(path, timestamp)
        path
      end

    manual = Path.join(tmp_dir, "hueworks_manual_20260709T120000.db")
    File.write!(manual, "manual")

    assert :ok = DatabaseMaintenance.prune_backups(tmp_dir, "hueworks_pre_migration_", 2)

    refute File.exists?(hd(automated))
    assert Enum.all?(tl(automated), &File.exists?/1)
    assert File.exists?(manual)
  end

  defp create_values_db!(path, table, values) do
    {:ok, conn} = Sqlite3.open(path)

    try do
      :ok = Sqlite3.execute(conn, "CREATE TABLE #{table} (name TEXT)")

      Enum.each(values, fn value ->
        :ok = Sqlite3.execute(conn, "INSERT INTO #{table} VALUES (#{sql_string(value)})")
      end)
    after
      Sqlite3.close(conn)
    end
  end

  defp table_values(path, table) do
    {:ok, conn} = Sqlite3.open(path, mode: :readonly)

    try do
      {:ok, statement} = Sqlite3.prepare(conn, "SELECT name FROM #{table} ORDER BY rowid")
      {:ok, rows} = Sqlite3.fetch_all(conn, statement)
      :ok = Sqlite3.release(conn, statement)

      Enum.map(rows, fn [value] -> value end)
    after
      Sqlite3.close(conn)
    end
  end

  defp sql_string(value) do
    "'" <> String.replace(value, "'", "''") <> "'"
  end
end
