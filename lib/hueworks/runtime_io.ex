defmodule Hueworks.RuntimeIO do
  @moduledoc """
  Enforces the rehearsal boundary that prevents communication with household services.
  """

  def disabled? do
    Application.get_env(:hueworks, :runtime_io_disabled, false) == true
  end

  def ensure_enabled do
    if disabled?(), do: {:error, :runtime_io_disabled}, else: :ok
  end
end
