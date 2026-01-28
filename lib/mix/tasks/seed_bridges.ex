defmodule Mix.Tasks.SeedBridges do
  use Mix.Task

  @shortdoc "Seed bridges with import_complete = false"

  @moduledoc """
  Seed bridges from secrets.env into the database.

  Usage:

      mix seed_bridges
  """

  @impl true
  def run(_args) do
    Mix.Task.run("app.start")
    Mix.Task.run("run", ["priv/repo/seeds.exs"])
  end
end
