defmodule Hueworks.Release do
  @moduledoc """
  Release-time helpers for migrations and idempotent bridge bootstrap.
  """

  require Logger

  @app :hueworks

  def migrate do
    load_app()

    for repo <- repos() do
      {:ok, _, _} =
        Ecto.Migrator.with_repo(repo, fn repo ->
          Ecto.Migrator.run(repo, :up, all: true)
        end)
    end

    :ok
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
