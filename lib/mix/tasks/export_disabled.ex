defmodule Mix.Tasks.ExportDisabled do
  use Mix.Task

  @shortdoc "Export disabled lights and groups to a JSON file"

  @moduledoc """
  Export disabled lights and groups for reuse during sync.

  Usage:

      mix export_disabled
      mix export_disabled path/to/file.json
  """

  alias Hueworks.Import.DisabledList

  @impl true
  def run(args) do
    Mix.Task.run("app.start")

    path =
      case args do
        [custom_path] -> custom_path
        _ -> DisabledList.default_path()
      end

    {:ok, saved_path} = DisabledList.export(path)
    Mix.shell().info("Saved disabled entities to #{saved_path}")
  end
end
