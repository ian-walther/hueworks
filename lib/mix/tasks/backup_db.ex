defmodule Mix.Tasks.BackupDb do
  use Mix.Task

  alias Hueworks.DatabaseMaintenance

  @shortdoc "Create a safe SQLite snapshot backup"

  @impl true
  def run(_args) do
    Mix.Task.run("app.config")

    case DatabaseMaintenance.backup(repo_db_path()) do
      {:ok, backup_path} ->
        Mix.shell().info("Created SQLite backup: #{backup_path}")

      {:error, reason} ->
        Mix.raise("Failed to create SQLite backup: #{format_reason(reason)}")
    end
  end

  defp repo_db_path do
    Application.fetch_env!(:hueworks, Hueworks.Repo)
    |> Keyword.fetch!(:database)
    |> Path.expand()
  end

  defp format_reason(reason), do: inspect(reason)
end
