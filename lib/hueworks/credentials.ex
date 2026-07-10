defmodule Hueworks.Credentials do
  @moduledoc """
  Runtime-resolved paths for persisted credential material.
  """

  @default_root Path.expand("../../priv/credentials", __DIR__)
  @caseta_staging_ttl_seconds 24 * 60 * 60

  def root_path do
    Application.get_env(:hueworks, :credentials_root, @default_root)
    |> Path.expand()
  end

  def caseta_dir do
    Path.join(root_path(), "caseta")
  end

  def caseta_staging_dir do
    Path.join(caseta_dir(), "staging")
  end

  def delete_paths(paths) do
    paths
    |> List.wrap()
    |> Enum.each(fn
      path when is_binary(path) -> File.rm(path)
      _path -> :ok
    end)

    :ok
  end

  def prune_stale_caseta_staging_files(max_age_seconds \\ @caseta_staging_ttl_seconds) do
    dir = caseta_staging_dir()

    if File.dir?(dir) do
      now = System.os_time(:second)

      dir
      |> File.ls!()
      |> Enum.each(fn name ->
        path = Path.join(dir, name)

        with {:ok, %File.Stat{type: :regular, mtime: mtime}} <- File.stat(path, time: :posix),
             true <- now - mtime > max_age_seconds do
          File.rm(path)
        else
          _ -> :ok
        end
      end)
    end

    :ok
  end
end
