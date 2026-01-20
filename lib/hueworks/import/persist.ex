defmodule Hueworks.Import.Persist do
  @moduledoc false

  def lights_by_source_id(bridge_id, source),
    do: Hueworks.Legacy.Import.Persist.lights_by_source_id(bridge_id, source)

  def groups_by_source_id(bridge_id, source),
    do: Hueworks.Legacy.Import.Persist.groups_by_source_id(bridge_id, source)

  def light_indexes,
    do: Hueworks.Legacy.Import.Persist.light_indexes()
end
