defmodule Hueworks.Credentials do
  @moduledoc """
  Runtime-resolved paths for persisted credential material.
  """

  @default_root Path.expand("../../priv/credentials", __DIR__)

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
end
