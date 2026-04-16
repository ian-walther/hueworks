defmodule Hueworks.Subscription.Z2MEventStream do
  @moduledoc """
  Manages Zigbee2MQTT MQTT subscriptions per bridge.
  """

  alias Hueworks.Subscription.GenericEventStream
  alias Hueworks.Subscription.Z2MEventStream.Connection



  def child_spec(opts) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [opts]},
      type: :worker,
      restart: :permanent,
      shutdown: 500
    }
  end
  def start_link(opts \\ []) do
    opts
    |> Keyword.put_new(:name, __MODULE__)
    |> Keyword.put_new(:bridge_type, :z2m)
    |> Keyword.put_new(:connection_module, Connection)
    |> GenericEventStream.start_link()
  end
end
