defmodule Mix.Tasks.RestoreDb do
  use Mix.Task

  alias Hueworks.DatabaseMaintenance

  @shortdoc "Restore a SQLite backup after validation"

  @impl true
  def run(args) do
    Mix.Task.run("app.config")

    {opts, _remaining, invalid} =
      OptionParser.parse(args,
        strict: [force: :boolean, backup: :string],
        aliases: [f: :force, b: :backup]
      )

    if invalid != [] do
      Mix.raise("Invalid restore_db options: #{inspect(invalid)}")
    end

    restore_opts =
      [force: Keyword.get(opts, :force, false)]
      |> maybe_put_backup_path(Keyword.get(opts, :backup))

    case DatabaseMaintenance.restore(repo_db_path(), restore_opts) do
      {:ok, result} ->
        Mix.shell().info("Restored SQLite database from: #{result.backup_path}")
        Mix.shell().info("Pre-restore recovery snapshot: #{result.recovery_path}")

      {:error, :force_required} ->
        Mix.raise("Refusing restore without --force")

      {:error, :application_running} ->
        Mix.raise("Refusing restore while HueWorks Repo is running in this BEAM")

      {:error, reason} ->
        Mix.raise("Failed to restore SQLite backup: #{format_reason(reason)}")
    end
  end

  defp repo_db_path do
    Application.fetch_env!(:hueworks, Hueworks.Repo)
    |> Keyword.fetch!(:database)
    |> Path.expand()
  end

  defp maybe_put_backup_path(opts, nil), do: opts
  defp maybe_put_backup_path(opts, backup_path), do: Keyword.put(opts, :backup_path, backup_path)

  defp format_reason(reason), do: inspect(reason)
end
