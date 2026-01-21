defmodule Hueworks.Subscription.HueEventStream.Connection do
  @moduledoc false

  use GenServer

  require Logger

  alias Hueworks.Subscription.HueEventStream.{Mapper, Parser}
  alias Hueworks.Control.Indexes

  def start_link(bridge) do
    GenServer.start_link(__MODULE__, bridge, [])
  end

  @impl true
  def init(bridge) do
    lights_by_id = Indexes.lights_by_source_id(bridge.id, :hue)
    groups_by_id = Indexes.groups_by_source_id(bridge.id, :hue)
    {group_light_ids, group_lights} = Mapper.load_group_maps(bridge.id)

    state = %{
      bridge: bridge,
      ref: nil,
      async_response: nil,
      buffer: "",
      lights_by_id: lights_by_id,
      groups_by_id: groups_by_id,
      group_light_ids: group_light_ids,
      group_lights: group_lights
    }

    send(self(), :connect)
    {:ok, state}
  end

  @impl true
  def handle_info(:connect, state) do
    api_key = state.bridge.credentials["api_key"]

    if is_binary(api_key) and api_key != "" do
      url = "https://#{state.bridge.host}/eventstream/clip/v2"
      headers = [
        {"hue-application-key", api_key},
        {"Accept", "text/event-stream"},
        {"Connection", "keep-alive"}
      ]

      case HTTPoison.get(url,
             headers,
             recv_timeout: :infinity,
             stream_to: self(),
             async: :once,
             hackney: [insecure: true]
           ) do
        {:ok, %HTTPoison.AsyncResponse{id: ref} = async_response} ->
          {:noreply, %{state | ref: ref, async_response: async_response, buffer: ""}}

        {:error, reason} ->
          Logger.warning("Hue SSE failed to connect to #{state.bridge.name} (#{state.bridge.host}): #{inspect(reason)}")
          schedule_reconnect()
          {:noreply, state}
      end
    else
      Logger.warning("Hue SSE missing api_key for #{state.bridge.name} (#{state.bridge.host})")
      schedule_reconnect()
      {:noreply, state}
    end
  end

  @impl true
  def handle_info(%HTTPoison.AsyncStatus{id: ref, code: _code}, %{ref: ref} = state) do
    HTTPoison.stream_next(state.async_response)
    {:noreply, state}
  end

  @impl true
  def handle_info(%HTTPoison.AsyncHeaders{id: ref, headers: _headers}, %{ref: ref} = state) do
    HTTPoison.stream_next(state.async_response)
    {:noreply, state}
  end

  @impl true
  def handle_info(%HTTPoison.AsyncChunk{id: ref, chunk: chunk}, %{ref: ref} = state) do
    {resources, rest} = Parser.consume(state.buffer, chunk)
    Enum.each(resources, &Mapper.handle_resource(&1, state))
    HTTPoison.stream_next(state.async_response)
    {:noreply, %{state | buffer: rest}}
  end

  @impl true
  def handle_info(%HTTPoison.AsyncEnd{id: ref}, %{ref: ref} = state) do
    schedule_reconnect()
    {:noreply, %{state | ref: nil, async_response: nil}}
  end

  @impl true
  def handle_info(%HTTPoison.Error{reason: reason}, state) do
    Logger.warning("Hue SSE error from #{state.bridge.name}: #{inspect(reason)}")
    schedule_reconnect()
    {:noreply, %{state | ref: nil, async_response: nil}}
  end

  @impl true
  def handle_info(_message, state) do
    {:noreply, state}
  end

  defp schedule_reconnect do
    Process.send_after(self(), :connect, 2_000)
  end
end
