defmodule Hueworks.ReleaseTest do
  use ExUnit.Case, async: false

  alias Hueworks.Release

  setup do
    tmp_dir =
      Path.join(System.tmp_dir!(), "hueworks-release-#{System.unique_integer([:positive])}")

    File.mkdir_p!(tmp_dir)
    db_path = Path.join(tmp_dir, "hueworks.db")
    File.write!(db_path, "database")
    Application.put_env(:hueworks, :release_test_db_path, db_path)
    Application.put_env(:hueworks, :release_test_pid, self())

    on_exit(fn ->
      Application.delete_env(:hueworks, :release_test_db_path)
      Application.delete_env(:hueworks, :release_test_pid)
      File.rm_rf!(tmp_dir)
    end)

    {:ok, db_path: db_path, tmp_dir: tmp_dir}
  end

  test "backs up before applying pending migrations and prunes automated backups", %{
    tmp_dir: tmp_dir
  } do
    assert :ok =
             Release.migrate_with_backup(
               repos: [__MODULE__.RepoStub],
               migrator: __MODULE__.PendingMigrator,
               maintenance: __MODULE__.MaintenanceStub,
               timestamp: "20260717T120000",
               retention: 5
             )

    expected = Path.join(tmp_dir, "backups/hueworks_pre_migration_20260717T120000.db")

    assert_receive {:backup, ^expected}
    assert_receive {:prune, backup_dir, "hueworks_pre_migration_", 5}
    assert backup_dir == Path.join(tmp_dir, "backups")
    assert_receive :migrate
  end

  test "does not create a redundant backup when no migrations are pending" do
    assert :ok =
             Release.migrate_with_backup(
               repos: [__MODULE__.RepoStub],
               migrator: __MODULE__.CurrentMigrator,
               maintenance: __MODULE__.MaintenanceStub
             )

    refute_receive {:backup, _path}
    assert_receive :migrate
  end

  test "aborts before migration when the safety backup fails" do
    assert_raise RuntimeError, ~r/pre-migration backup failed/, fn ->
      Release.migrate_with_backup(
        repos: [__MODULE__.RepoStub],
        migrator: __MODULE__.PendingMigrator,
        maintenance: __MODULE__.FailedMaintenance
      )
    end

    refute_receive :migrate
  end

  defmodule RepoStub do
    def config do
      [database: Application.fetch_env!(:hueworks, :release_test_db_path)]
    end
  end

  defmodule PendingMigrator do
    def with_repo(repo, fun), do: {:ok, fun.(repo), []}
    def migrations(_repo), do: [{:up, 1, "old"}, {:down, 2, "new"}]

    def run(_repo, :up, all: true) do
      send(Application.fetch_env!(:hueworks, :release_test_pid), :migrate)
      []
    end
  end

  defmodule CurrentMigrator do
    def with_repo(repo, fun), do: {:ok, fun.(repo), []}
    def migrations(_repo), do: [{:up, 1, "current"}]

    def run(_repo, :up, all: true) do
      send(Application.fetch_env!(:hueworks, :release_test_pid), :migrate)
      []
    end
  end

  defmodule MaintenanceStub do
    def backup(_db_path, backup_path: backup_path) do
      send(Application.fetch_env!(:hueworks, :release_test_pid), {:backup, backup_path})
      {:ok, backup_path}
    end

    def prune_backups(dir, prefix, retention) do
      send(
        Application.fetch_env!(:hueworks, :release_test_pid),
        {:prune, dir, prefix, retention}
      )

      :ok
    end
  end

  defmodule FailedMaintenance do
    def backup(_db_path, backup_path: _backup_path), do: {:error, :read_only}
    def prune_backups(_dir, _prefix, _retention), do: :ok
  end
end
