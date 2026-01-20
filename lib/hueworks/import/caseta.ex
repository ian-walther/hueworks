defmodule Hueworks.Import.Caseta do
  @moduledoc false

  def import(data), do: Hueworks.Legacy.Import.Caseta.import(data)
  def normalize(data), do: Hueworks.Legacy.Import.Caseta.normalize(data)
end
