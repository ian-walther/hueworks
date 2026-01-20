defmodule Hueworks.Import.SaveState do
  @moduledoc false

  def default_path, do: Hueworks.Legacy.Import.SaveState.default_path()
  def export(path \\ default_path()), do: Hueworks.Legacy.Import.SaveState.export(path)
  def load(path \\ default_path()), do: Hueworks.Legacy.Import.SaveState.load(path)
  def apply(state), do: Hueworks.Legacy.Import.SaveState.apply(state)
end
