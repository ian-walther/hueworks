defmodule Mix.Tasks.RestoreDb do
  use Mix.Task

  @shortdoc "Restore the most recent SQLite database backup"

  @impl true
  def run(_args) do
    Mix.Task.run("app.config")

    db_path =
      Application.fetch_env!(:hueworks, Hueworks.Repo)
      |> Keyword.fetch!(:database)
      |> Path.expand()

    ext = Path.extname(db_path)
    base = Path.rootname(db_path)
    pattern = base <> "_????????T??????" <> ext

    backup =
      pattern
      |> Path.wildcard()
      |> Enum.sort()
      |> List.last()

    if is_nil(backup) do
      Mix.raise("No backups found for pattern: #{pattern}")
    end

    remove_if_exists(db_path)
    remove_if_exists(db_path <> "-shm")
    remove_if_exists(db_path <> "-wal")

    rename_if_exists(backup, db_path)
    rename_if_exists(backup <> "-shm", db_path <> "-shm")
    rename_if_exists(backup <> "-wal", db_path <> "-wal")
  end

  defp remove_if_exists(path) do
    if File.exists?(path) do
      case File.rm(path) do
        :ok ->
          Mix.shell().info("Removed #{path}")

        {:error, reason} ->
          Mix.raise("Failed to remove #{path}: #{inspect(reason)}")
      end
    end
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
