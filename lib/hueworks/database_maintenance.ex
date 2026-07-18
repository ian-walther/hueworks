defmodule Hueworks.DatabaseMaintenance do
  @moduledoc """
  Safe SQLite backup and restore helpers for maintenance Mix tasks.
  """

  alias Exqlite.Sqlite3

  def backup(db_path, opts \\ []) when is_binary(db_path) and is_list(opts) do
    db_path = Path.expand(db_path)
    timestamp = Keyword.get_lazy(opts, :timestamp, &timestamp/0)

    backup_path =
      opts |> Keyword.get(:backup_path, timestamped_path(db_path, timestamp)) |> Path.expand()

    with :ok <- require_existing_file(db_path),
         :ok <- require_absent_file(backup_path),
         :ok <- File.mkdir_p(Path.dirname(backup_path)),
         :ok <- vacuum_into(db_path, backup_path) do
      {:ok, backup_path}
    end
  end

  def restore(db_path, opts \\ []) when is_binary(db_path) and is_list(opts) do
    db_path = Path.expand(db_path)
    force? = Keyword.get(opts, :force, false)
    active_check = Keyword.get(opts, :active_check, &application_running?/0)
    timestamp = Keyword.get_lazy(opts, :timestamp, &timestamp/0)

    with :ok <- require_force(force?),
         :ok <- require_inactive(active_check),
         {:ok, backup_path} <- resolve_backup_path(db_path, opts),
         :ok <- integrity_check(backup_path),
         {:ok, temp_path} <- copy_backup_to_temp(backup_path, db_path, timestamp),
         :ok <- integrity_check(temp_path),
         {:ok, recovery_path} <- recovery_snapshot(db_path, timestamp),
         :ok <- File.rename(temp_path, db_path),
         :ok <- remove_sidecars(db_path) do
      {:ok, %{restored_path: db_path, backup_path: backup_path, recovery_path: recovery_path}}
    else
      {:error, _reason} = error -> error
    end
  end

  def latest_backup_path(db_path) when is_binary(db_path) do
    db_path = Path.expand(db_path)
    ext = Path.extname(db_path)
    base = Path.rootname(db_path)
    pattern = base <> "_????????T??????" <> ext

    pattern
    |> Path.wildcard()
    |> Enum.sort()
    |> List.last()
    |> case do
      nil -> {:error, {:no_backups_found, pattern}}
      path -> {:ok, Path.expand(path)}
    end
  end

  def application_running? do
    Process.whereis(Hueworks.Repo)
    |> is_pid()
  end

  def prune_backups(dir, prefix, retention)
      when is_binary(dir) and is_binary(prefix) and is_integer(retention) and retention >= 1 do
    paths =
      dir
      |> Path.join("#{prefix}*")
      |> Path.wildcard()
      |> Enum.sort(:desc)
      |> Enum.drop(retention)

    Enum.reduce_while(paths, :ok, fn path, :ok ->
      case File.rm(path) do
        :ok -> {:cont, :ok}
        {:error, :enoent} -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, {:prune_failed, path, reason}}}
      end
    end)
  end

  defp require_existing_file(path) do
    if File.regular?(path), do: :ok, else: {:error, {:missing_database, path}}
  end

  defp require_absent_file(path) do
    if File.exists?(path), do: {:error, {:backup_exists, path}}, else: :ok
  end

  defp require_force(true), do: :ok
  defp require_force(_force), do: {:error, :force_required}

  defp require_inactive(active_check) when is_function(active_check, 0) do
    if active_check.(), do: {:error, :application_running}, else: :ok
  end

  defp resolve_backup_path(db_path, opts) do
    case Keyword.get(opts, :backup_path) do
      nil -> latest_backup_path(db_path)
      path when is_binary(path) -> {:ok, Path.expand(path)}
    end
  end

  defp copy_backup_to_temp(backup_path, db_path, timestamp) do
    temp_path = db_path <> ".restore-#{timestamp}.tmp"

    case File.rm(temp_path) do
      :ok ->
        copy_backup_to_temp_path(backup_path, temp_path)

      {:error, :enoent} ->
        copy_backup_to_temp_path(backup_path, temp_path)

      {:error, reason} ->
        {:error, {:copy_failed, reason}}
    end
  end

  defp copy_backup_to_temp_path(backup_path, temp_path) do
    case File.cp(backup_path, temp_path) do
      :ok -> {:ok, temp_path}
      {:error, reason} -> {:error, {:copy_failed, reason}}
    end
  end

  defp recovery_snapshot(db_path, timestamp) do
    if File.regular?(db_path) do
      recovery_path = timestamped_path(db_path, "pre_restore_#{timestamp}")

      case backup(db_path, backup_path: recovery_path) do
        {:ok, ^recovery_path} -> {:ok, recovery_path}
        {:error, reason} -> {:error, {:recovery_failed, reason}}
      end
    else
      {:ok, nil}
    end
  end

  defp vacuum_into(db_path, target_path) do
    with {:ok, conn} <- Sqlite3.open(db_path, mode: :readwrite) do
      try do
        case Sqlite3.execute(conn, "VACUUM INTO #{sql_string(target_path)}") do
          :ok -> :ok
          {:error, reason} -> {:error, {:backup_failed, reason}}
        end
      after
        Sqlite3.close(conn)
      end
    else
      {:error, reason} -> {:error, {:open_failed, reason}}
    end
  end

  defp integrity_check(path) do
    with :ok <- require_existing_file(path),
         {:ok, conn} <- Sqlite3.open(path, mode: :readonly) do
      try do
        run_integrity_check(conn)
      after
        Sqlite3.close(conn)
      end
    else
      {:error, {:missing_database, _path}} = error -> error
      {:error, reason} -> {:error, {:integrity_check_failed, reason}}
    end
  end

  defp run_integrity_check(conn) do
    with {:ok, statement} <- Sqlite3.prepare(conn, "PRAGMA integrity_check") do
      try do
        case Sqlite3.fetch_all(conn, statement) do
          {:ok, [["ok"]]} -> :ok
          {:ok, rows} -> {:error, {:integrity_check_failed, rows}}
          {:error, reason} -> {:error, {:integrity_check_failed, reason}}
        end
      after
        Sqlite3.release(conn, statement)
      end
    else
      {:error, reason} -> {:error, {:integrity_check_failed, reason}}
    end
  end

  defp remove_sidecars(db_path) do
    [db_path <> "-shm", db_path <> "-wal"]
    |> Enum.reduce(:ok, fn path, :ok ->
      case File.rm(path) do
        :ok -> :ok
        {:error, :enoent} -> :ok
        {:error, reason} -> {:error, {:remove_sidecar_failed, path, reason}}
      end
    end)
  end

  defp timestamped_path(path, suffix) do
    ext = Path.extname(path)
    base = Path.rootname(path)
    base <> "_" <> suffix <> ext
  end

  defp timestamp do
    NaiveDateTime.utc_now()
    |> NaiveDateTime.truncate(:second)
    |> Calendar.strftime("%Y%m%dT%H%M%S")
  end

  defp sql_string(value) do
    "'" <> String.replace(value, "'", "''") <> "'"
  end
end
