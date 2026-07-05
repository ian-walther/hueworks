defmodule Mix.Tasks.LinkBridgeImports do
  use Mix.Task

  @shortdoc "Link canonical entities across imports"

  @moduledoc """
  This task is retired. Manual reimport now performs scoped duplicate handling
  for newly reviewed bridge rows and must not run a global canonical-link pass.

  Usage:

      mix link_bridge_imports
  """

  @impl true
  def run(_args) do
    Mix.raise("""
    mix link_bridge_imports is retired.

    Use manual bridge reimport review instead so duplicate handling stays scoped
    to newly imported rows and does not mutate existing canonical links globally.
    """)
  end
end
