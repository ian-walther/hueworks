defmodule Hueworks.Import.Hue do
  @moduledoc false

  def import(data), do: Hueworks.Legacy.Import.Hue.import(data)
  def normalize(data), do: Hueworks.Legacy.Import.Hue.normalize(data)
end
