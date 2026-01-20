defmodule Mix.Tasks.BackupDb do
  use Mix.Task

  @shortdoc "Back up the SQLite database with a timestamp suffix"

  @impl true
  def run(_args) do
    Mix.Task.run("app.config")

    db_path =
      Application.fetch_env!(:hueworks, Hueworks.Repo)
      |> Keyword.fetch!(:database)
      |> Path.expand()

    timestamp = timestamp()
    backup_path = insert_timestamp(db_path, timestamp)

    rename_if_exists(db_path, backup_path)
    rename_if_exists(db_path <> "-shm", backup_path <> "-shm")
    rename_if_exists(db_path <> "-wal", backup_path <> "-wal")
  end

  defp timestamp do
    NaiveDateTime.utc_now()
    |> NaiveDateTime.truncate(:second)
    |> Calendar.strftime("%Y%m%dT%H%M%S")
  end

  defp insert_timestamp(path, timestamp) do
    ext = Path.extname(path)
    base = Path.rootname(path)
    base <> "_" <> timestamp <> ext
  end

  defp rename_if_exists(from, to) do
    if File.exists?(from) do
      case File.rename(from, to) do
        :ok ->
          Mix.shell().info("Moved #{from} -> #{to}")

        {:error, reason} ->
          Mix.raise("Failed to move #{from} -> #{to}: #{inspect(reason)}")
      end
    else
      Mix.shell().info("Skipping missing file: #{from}")
    end
  end
end
