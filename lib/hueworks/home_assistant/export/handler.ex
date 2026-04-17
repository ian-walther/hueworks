defmodule Hueworks.HomeAssistant.Export.Handler do
  @moduledoc false

  use Tortoise.Handler

  @type state :: %{
          server: pid(),
          client_id: String.t(),
          subscriptions: [{String.t(), non_neg_integer()}],
          subscribed?: boolean()
        }

  @spec init(list(term())) :: {:ok, state()}
  def init([server, client_id, topic_filters]) do
    subscriptions =
      topic_filters
      |> List.wrap()
      |> Enum.map(&{&1, 0})

    {:ok,
     %{
       server: server,
       client_id: client_id,
       subscriptions: subscriptions,
       subscribed?: false
     }}
  end

  @spec connection(atom(), state()) :: {:ok, state()}
  def connection(:up, state) do
    {:ok, _ref} = Tortoise.Connection.subscribe(state.client_id, state.subscriptions)
    send(state.server, {:mqtt_connected, state.client_id})
    {:ok, %{state | subscribed?: true}}
  end

  def connection(:down, state), do: {:ok, %{state | subscribed?: false}}
  def connection(_status, state), do: {:ok, state}

  @spec subscription(term(), term(), state()) :: {:ok, state()}
  def subscription(_status, _topic_filter, state), do: {:ok, state}

  @spec handle_message(list(String.t()), term(), state()) :: {:ok, state()}
  def handle_message(topic_levels, payload, state) do
    send(state.server, {:mqtt_message, topic_levels, payload})
    {:ok, state}
  end

  @spec terminate(term(), state()) :: :ok
  def terminate(_reason, _state), do: :ok
end
