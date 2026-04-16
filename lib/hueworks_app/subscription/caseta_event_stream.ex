defmodule Hueworks.Subscription.CasetaEventStream do
  @moduledoc """
  Manages Caseta LEAP connections per bridge.
  """

  alias Hueworks.Subscription.CasetaEventStream.Connection
  alias Hueworks.Subscription.GenericEventStream



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
    |> Keyword.put_new(:bridge_type, :caseta)
    |> Keyword.put_new(:connection_module, Connection)
    |> GenericEventStream.start_link()
  end
end
