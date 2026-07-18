defmodule Hueworks.Release do
  @moduledoc """
  Release-time helpers for migrations and idempotent bridge bootstrap.
  """

  require Logger

  @app :hueworks
  @pre_migration_prefix "hueworks_pre_migration_"
  @manual_prefix "hueworks_manual_"
  @default_backup_retention 5

  def migrate, do: migrate_with_backup()

  def migrate_with_backup(opts \\ []) do
    load_app()
    migrator = Keyword.get(opts, :migrator, Ecto.Migrator)
    maintenance = Keyword.get(opts, :maintenance, Hueworks.DatabaseMaintenance)
    configured_repos = Keyword.get(opts, :repos, repos())

    for repo <- configured_repos do
      {:ok, _, _} =
        migrator.with_repo(repo, fn repo ->
          maybe_backup_pending_migrations(repo, migrator, maintenance, opts)
          migrator.run(repo, :up, all: true)
        end)
    end

    :ok
  end

  def backup do
    load_app()

    Enum.each(repos(), fn repo ->
      db_path = database_path(repo)
      path = backup_path(db_path, @manual_prefix, timestamp(), backup_dir(db_path))

      case Hueworks.DatabaseMaintenance.backup(db_path, backup_path: path) do
        {:ok, backup_path} -> IO.puts("[hueworks] created database backup: #{backup_path}")
        {:error, reason} -> raise "database backup failed: #{inspect(reason)}"
      end
    end)

    :ok
  end

  def restore(backup_path, confirmation) when is_binary(backup_path) do
    load_app()

    if confirmation != "RESTORE" do
      raise "restore requires the exact confirmation value RESTORE"
    end

    case repos() do
      [repo] ->
        db_path = database_path(repo)

        case Hueworks.DatabaseMaintenance.restore(db_path,
               backup_path: backup_path,
               force: true
             ) do
          {:ok, result} ->
            IO.puts("[hueworks] restored database from: #{result.backup_path}")
            IO.puts("[hueworks] pre-restore recovery snapshot: #{result.recovery_path}")
            :ok

          {:error, reason} ->
            raise "database restore failed: #{inspect(reason)}"
        end

      configured_repos ->
        raise "release restore expects one repository, found #{length(configured_repos)}"
    end
  end

  def seed_bridges do
    load_app()

    path = Hueworks.BridgeSeeds.default_path()

    if File.regular?(path) do
      start_repos()

      case Hueworks.BridgeSeeds.seed_from_file(path) do
        {:ok, count} ->
          Logger.info("Seeded #{count} bridge definitions from #{path}")
          :ok

        {:error, reason} ->
          raise "Bridge seed failed from #{path}: #{inspect(reason)}"
      end
    else
      Logger.info("Bridge seed file not found at #{path}; skipping bridge bootstrap")
      :ok
    end
  end

  defp load_app do
    Application.load(@app)
  end

  defp repos do
    Application.fetch_env!(@app, :ecto_repos)
  end

  defp maybe_backup_pending_migrations(repo, migrator, maintenance, opts) do
    pending? =
      Enum.any?(migrator.migrations(repo), fn {status, _version, _name} -> status == :down end)

    db_path = database_path(repo)

    if pending? and File.regular?(db_path) do
      timestamp = Keyword.get_lazy(opts, :timestamp, &timestamp/0)
      dir = Keyword.get(opts, :backup_dir, backup_dir(db_path))
      retention = Keyword.get(opts, :retention, backup_retention())
      path = backup_path(db_path, @pre_migration_prefix, timestamp, dir)

      case maintenance.backup(db_path, backup_path: path) do
        {:ok, backup_path} ->
          Logger.info("Created pre-migration database backup at #{backup_path}")
          :ok = maintenance.prune_backups(dir, @pre_migration_prefix, retention)

        {:error, reason} ->
          raise "pre-migration backup failed; migrations were not run: #{inspect(reason)}"
      end
    end
  end

  defp database_path(repo) do
    repo.config()
    |> Keyword.fetch!(:database)
    |> Path.expand()
  end

  defp backup_dir(db_path) do
    case System.get_env("DATABASE_BACKUP_DIR") do
      value when is_binary(value) and value != "" -> Path.expand(value)
      _value -> Path.join(Path.dirname(db_path), "backups")
    end
  end

  defp backup_retention do
    case Integer.parse(
           System.get_env("DATABASE_BACKUP_RETENTION", "#{@default_backup_retention}")
         ) do
      {retention, ""} when retention >= 1 -> retention
      _other -> @default_backup_retention
    end
  end

  defp backup_path(db_path, prefix, timestamp, dir) do
    extension = Path.extname(db_path)
    Path.join(dir, "#{prefix}#{timestamp}#{extension}")
  end

  defp timestamp do
    NaiveDateTime.utc_now()
    |> NaiveDateTime.truncate(:second)
    |> Calendar.strftime("%Y%m%dT%H%M%S")
  end

  defp start_repos do
    Enum.each([:crypto, :ssl, :telemetry, :ecto, :ecto_sql, :ecto_sqlite3], fn app ->
      {:ok, _started} = Application.ensure_all_started(app)
    end)

    Enum.each(repos(), fn repo ->
      case repo.start_link(pool_size: 2) do
        {:ok, _pid} -> :ok
        {:error, {:already_started, _pid}} -> :ok
      end
    end)
  end
end
