defmodule Hueworks.DebugLogging do
  @moduledoc """
  Runtime toggle for verbose planner/control debugging logs.
  """

  require Logger

  def enabled? do
    Application.get_env(:hueworks, :advanced_debug_logging, false)
  end

  def info(message) when is_binary(message) do
    if enabled?() do
      Logger.info(message)
    else
      :ok
    end
  end
end
