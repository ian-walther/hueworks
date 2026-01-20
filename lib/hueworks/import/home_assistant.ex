defmodule Hueworks.Import.HomeAssistant do
  @moduledoc false

  def import(data), do: Hueworks.Legacy.Import.HomeAssistant.import(data)
  def normalize(data), do: Hueworks.Legacy.Import.HomeAssistant.normalize(data)
end
