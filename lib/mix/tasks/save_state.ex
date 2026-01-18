defmodule Mix.Tasks.SaveState do
  use Mix.Task

  @shortdoc "Export light/group state overrides to a JSON file"

  @moduledoc """
  Export light/group state overrides for reuse during sync.

  Usage:

      mix save_state
      mix save_state path/to/file.json
  """

  alias Hueworks.Import.SaveState

  @impl true
  def run(args) do
    Mix.Task.run("app.start")

    path =
      case args do
        [custom_path] -> custom_path
        _ -> SaveState.default_path()
      end

    {:ok, saved_path} = SaveState.export(path)
    Mix.shell().info("Saved state overrides to #{saved_path}")
  end
end
