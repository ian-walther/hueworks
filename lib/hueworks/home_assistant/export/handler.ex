defmodule Hueworks.HomeAssistant.Export.Handler do
  @moduledoc false

  use Tortoise.Handler

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

  def connection(:up, state) do
    case Tortoise.Connection.subscribe(state.client_id, state.subscriptions) do
      {:ok, _ref} ->
        send(state.server, {:mqtt_connected, state.client_id})
        {:ok, %{state | subscribed?: true}}

      {:error, _reason} ->
        {:ok, %{state | subscribed?: false}}
    end
  end

  def connection(:down, state), do: {:ok, %{state | subscribed?: false}}
  def connection(_status, state), do: {:ok, state}
  def subscription(_status, _topic_filter, state), do: {:ok, state}

  def handle_message(topic_levels, payload, state) do
    send(state.server, {:mqtt_message, topic_levels, payload})
    {:ok, state}
  end

  def terminate(_reason, _state), do: :ok
end
