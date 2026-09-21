defmodule Hueworks.Control.Bootstrap.Observations do
  @moduledoc false

  alias Hueworks.Control.State

  def capture(type, entities) do
    Map.new(entities, fn {source_id, entity} ->
      {source_id, {entity, State.observation_version(type, entity.id)}}
    end)
  end

  # A snapshot request can finish after a newer stream event. Do not replace
  # that observation with an older HTTP/MQTT snapshot.
  def put(type, {entity, version}, attrs) when map_size(attrs) > 0 do
    State.put_if_unobserved_since(type, entity.id, attrs, version)
  end

  def put(_type, _entry, _attrs), do: :ok
end
