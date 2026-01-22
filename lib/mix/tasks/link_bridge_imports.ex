defmodule Mix.Tasks.LinkBridgeImports do
  use Mix.Task

  @shortdoc "Link canonical entities across imports"

  @moduledoc """
  Run the link step to connect canonical lights and groups.

  Usage:

      mix link_bridge_imports
  """

  alias Hueworks.Import.Link

  @impl true
  def run(_args) do
    Mix.Task.run("app.start")
    :ok = Link.apply()
  end
end
