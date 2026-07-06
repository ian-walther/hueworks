defmodule Hueworks.Import.Identifiers do
  @moduledoc false

  alias Hueworks.Import.{Normalize, Source}

  def light_external_id(light) do
    source = Source.normalize(Normalize.fetch(light, :source))
    identifiers = Normalize.fetch(light, :identifiers) || %{}
    metadata = Normalize.fetch(light, :metadata) || %{}
    source_id = Normalize.normalize_source_id(Normalize.fetch(light, :source_id))

    case source do
      :hue ->
        Normalize.fetch(metadata, :uniqueid) ||
          Normalize.fetch(metadata, "uniqueid") ||
          Normalize.fetch(identifiers, :mac) ||
          Normalize.fetch(identifiers, "mac") ||
          source_id

      :ha ->
        Normalize.fetch(metadata, :unique_id) ||
          Normalize.fetch(metadata, "unique_id") ||
          Normalize.fetch(metadata, :entity_id) ||
          Normalize.fetch(metadata, "entity_id") ||
          source_id

      :caseta ->
        Normalize.fetch(metadata, :device_id) ||
          Normalize.fetch(metadata, "device_id") ||
          Normalize.fetch(identifiers, :serial) ||
          Normalize.fetch(identifiers, "serial") ||
          source_id

      :z2m ->
        Normalize.normalize_source_id(
          Normalize.fetch(metadata, :ieee_address) ||
            Normalize.fetch(metadata, "ieee_address") ||
            Normalize.fetch(identifiers, :ieee) ||
            Normalize.fetch(identifiers, "ieee") ||
            source_id
        )

      _ ->
        source_id
    end
  end

  def group_external_id(group) do
    source = Source.normalize(Normalize.fetch(group, :source))
    metadata = Normalize.fetch(group, :metadata) || %{}
    source_id = Normalize.normalize_source_id(Normalize.fetch(group, :source_id))

    case source do
      :ha ->
        Normalize.fetch(metadata, :unique_id) ||
          Normalize.fetch(metadata, "unique_id") ||
          Normalize.fetch(metadata, :entity_id) ||
          Normalize.fetch(metadata, "entity_id") ||
          source_id

      :caseta ->
        Normalize.fetch(metadata, :device_id) ||
          Normalize.fetch(metadata, "device_id") ||
          source_id

      :z2m ->
        Normalize.normalize_source_id(
          Normalize.fetch(metadata, :id) ||
            Normalize.fetch(metadata, "id") ||
            source_id
        )

      _ ->
        source_id
    end
  end
end
