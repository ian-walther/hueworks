defmodule Mix.Tasks.ResetSync do
  use Mix.Task

  @shortdoc "Exports disabled entities, resets the DB, and runs sync"

  @moduledoc """
  Usage:

      mix reset_sync

  Runs:
    1) mix save_state
    2) mix ecto.reset
    3) mix sync
  """

  @impl true
  def run(_args) do
    run_task("save_state")
    run_task("ecto.drop")
    run_task("ecto.create")
    run_task("ecto.migrate")
    run_task("run", ["priv/repo/seeds.exs"])
    run_task("sync")
  end

  defp run_task(task, args \\ []) do
    Mix.Task.reenable(task)
    Mix.Task.run(task, args)
  end
end
