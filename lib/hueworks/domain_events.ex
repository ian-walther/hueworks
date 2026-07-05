defmodule Hueworks.DomainEvents do
  @moduledoc false

  alias Hueworks.Schemas.{PresenceInput, Scene}
  alias Phoenix.PubSub

  @topic "domain_events"

  def topic, do: @topic

  def scene_saved(%Scene{} = scene), do: broadcast({:scene_saved, scene})
  def scene_deleted(%Scene{} = scene), do: broadcast({:scene_deleted, scene})

  def presence_input_changed(%PresenceInput{} = input),
    do: broadcast({:presence_input_changed, input})

  def presence_input_deleted(input_id) when is_integer(input_id),
    do: broadcast({:presence_input_deleted, input_id})

  defp broadcast(message) do
    PubSub.broadcast(Hueworks.PubSub, @topic, message)
  end
end
