defmodule Hueworks.Control.HueEventStream.Connection do
  @moduledoc false

  use GenServer

  require Logger

  import Ecto.Query, only: [from: 2]

  alias Hueworks.Control.State
  alias Hueworks.Import.Persist
  alias Hueworks.Groups.Group
  alias Hueworks.Groups.GroupLight
  alias Hueworks.Repo

  def start_link(bridge) do
    GenServer.start_link(__MODULE__, bridge, [])
  end

  @impl true
  def init(bridge) do
    lights_by_id = Persist.lights_by_source_id(bridge.id, :hue)
    groups_by_id = Persist.groups_by_source_id(bridge.id, :hue)

    state = %{
      bridge: bridge,
      ref: nil,
      async_response: nil,
      buffer: "",
      lights_by_id: lights_by_id,
      groups_by_id: groups_by_id,
      group_light_ids: load_group_light_ids(bridge.id),
      group_lights: load_group_lights(bridge.id),
      unknown_messages: 0
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

      Logger.info("Hue SSE connecting to #{state.bridge.name} (#{state.bridge.host})")

      case HTTPoison.get(url,
             headers,
             recv_timeout: :infinity,
             stream_to: self(),
             async: :once,
             hackney: [insecure: true]
           ) do
        {:ok, %HTTPoison.AsyncResponse{id: ref} = async_response} ->
          Logger.info("Hue SSE connected to #{state.bridge.name} (#{state.bridge.host})")
          {:noreply, %{state | ref: ref, async_response: async_response, buffer: ""}}

        {:error, reason} ->
          Logger.warn("Hue SSE failed to connect to #{state.bridge.name} (#{state.bridge.host}): #{inspect(reason)}")
          schedule_reconnect()
          {:noreply, state}
      end
    else
      Logger.warn("Hue SSE missing api_key for #{state.bridge.name} (#{state.bridge.host})")
      schedule_reconnect()
      {:noreply, state}
    end
  end

  @impl true
  def handle_info(%HTTPoison.AsyncStatus{id: ref, code: _code}, %{ref: ref} = state) do
    Logger.info("Hue SSE status received for #{state.bridge.name}")
    HTTPoison.stream_next(state.async_response)
    {:noreply, state}
  end

  @impl true
  def handle_info(%HTTPoison.AsyncHeaders{id: ref, headers: _headers}, %{ref: ref} = state) do
    Logger.info("Hue SSE headers received for #{state.bridge.name}")
    HTTPoison.stream_next(state.async_response)
    {:noreply, state}
  end

  @impl true
  def handle_info(%HTTPoison.AsyncChunk{id: ref, chunk: chunk}, %{ref: ref} = state) do
    Logger.info("Hue SSE chunk received from #{state.bridge.name} (#{byte_size(chunk)} bytes)")
    {events, rest} = split_events(state.buffer <> chunk)
    Enum.each(events, &handle_event_payload(&1, state))
    HTTPoison.stream_next(state.async_response)
    {:noreply, %{state | buffer: rest}}
  end

  @impl true
  def handle_info(%HTTPoison.AsyncEnd{id: ref}, %{ref: ref} = state) do
    Logger.warn("Hue SSE disconnected from #{state.bridge.name}")
    schedule_reconnect()
    {:noreply, %{state | ref: nil, async_response: nil}}
  end

  @impl true
  def handle_info(%HTTPoison.Error{reason: reason}, state) do
    Logger.warn("Hue SSE error from #{state.bridge.name}: #{inspect(reason)}")
    schedule_reconnect()
    {:noreply, %{state | ref: nil, async_response: nil}}
  end

  @impl true
  def handle_info(message, state) do
    if state.unknown_messages < 5 do
      Logger.info("Hue SSE unexpected message for #{state.bridge.name}: #{inspect(message)}")
    end

    {:noreply, %{state | unknown_messages: state.unknown_messages + 1}}
  end

  defp split_events(buffer) do
    normalized = String.replace(buffer, "\r\n", "\n")
    parts = String.split(normalized, "\n\n")

    case parts do
      [] ->
        {[], ""}

      [single] ->
        {[], single}

      _ ->
        {Enum.drop(parts, -1), List.last(parts)}
    end
  end

  defp handle_event_payload(payload, state) do
    data =
      payload
      |> String.split("\n")
      |> Enum.filter(&String.starts_with?(&1, "data:"))
      |> Enum.map(fn line -> String.trim_leading(line, "data:") |> String.trim() end)
      |> Enum.join("\n")

    if data != "" do
      case Jason.decode(data) do
        {:ok, events} when is_list(events) ->
          Logger.info("Hue SSE envelopes from #{state.bridge.name}: #{length(events)}")
          Enum.each(events, &handle_envelope(&1, state))

        {:ok, event} when is_map(event) ->
          Logger.info("Hue SSE envelope from #{state.bridge.name}")
          handle_envelope(event, state)

        _ ->
          :ok
      end
    end
  end

  defp handle_envelope(%{"data" => data} = _event, state) when is_list(data) do
    Enum.each(data, &handle_resource(&1, state))
  end

  defp handle_envelope(event, state) when is_map(event) do
    handle_resource(event, state)
  end

  defp handle_envelope(_event, _state), do: :ok

  defp handle_resource(%{"type" => "light"} = resource, state) do
    with {:ok, v1_id} <- v1_id_from_event(resource, "/lights/"),
         %{id: db_id} <- Map.get(state.lights_by_id, v1_id) do
      if Map.has_key?(resource, "color_temperature") do
        Logger.info(
          "Hue SSE color_temperature for #{state.bridge.name} light #{v1_id}: " <>
            "#{inspect(resource["color_temperature"])}"
        )
      end

      attrs = event_state_from_light(resource)

      if Map.has_key?(attrs, :kelvin) do
        Logger.info(
          "Hue SSE kelvin update for #{state.bridge.name} light #{v1_id}: #{attrs.kelvin}K"
        )
      end

      State.put(:light, db_id, attrs)
      maybe_update_groups_from_light(state, db_id, attrs)
    else
      _ -> :ok
    end
  end

  defp handle_resource(%{"type" => "grouped_light"} = resource, state) do
    v1_id_result = v1_group_id(resource)

    with {:ok, v1_id} <- v1_id_result,
         %{id: db_id, name: name} <- Map.get(state.groups_by_id, v1_id) do
      attrs = event_state_from_group(resource)
      Logger.info("Hue SSE grouped_light mapped for #{state.bridge.name}: #{v1_id} (#{name}) #{inspect(attrs)}")
      State.put(:group, db_id, attrs)
    else
      _ ->
        Logger.info(
          "Hue SSE grouped_light unmapped for #{state.bridge.name}: " <>
            "id_v1=#{inspect(resource["id_v1"])} owner.id_v1=#{inspect(get_in(resource, ["owner", "id_v1"]))}"
        )

        :ok
    end
  end

  defp handle_resource(_resource, _state), do: :ok

  defp v1_id_from_event(event, prefix) do
    v1_id_from_id_v1(event["id_v1"], prefix)
  end

  defp v1_id_from_id_v1(id_v1, prefix) when is_binary(id_v1) do
    case String.split(id_v1, prefix) do
      [_before, id] when id != "" -> {:ok, id}
      _ -> :error
    end
  end

  defp v1_id_from_id_v1(_id_v1, _prefix), do: :error

  defp v1_group_id(resource) do
    case v1_id_from_event(resource, "/groups/") do
      {:ok, _id} = ok ->
        ok

      :error ->
        owner_id_v1 = get_in(resource, ["owner", "id_v1"])
        v1_id_from_id_v1(owner_id_v1, "/groups/")
    end
  end

  defp event_state_from_light(event) do
    %{}
    |> Map.merge(extract_power(event))
    |> Map.merge(extract_brightness(event))
    |> Map.merge(extract_kelvin(event))
  end

  defp event_state_from_group(event), do: event_state_from_light(event)

  defp extract_power(event) do
    case get_in(event, ["on", "on"]) do
      true -> %{power: :on}
      false -> %{power: :off}
      _ -> %{}
    end
  end

  defp extract_brightness(event) do
    case get_in(event, ["dimming", "brightness"]) do
      value when is_number(value) ->
        %{brightness: clamp(round(value), 1, 100)}

      _ ->
        %{}
    end
  end

  defp extract_kelvin(event) do
    mired =
      case event["color_temperature"] do
        %{"mirek" => value} -> to_number(value)
        %{:mirek => value} -> to_number(value)
        value -> to_number(value)
      end

    if is_number(mired) and mired > 0 do
      %{kelvin: round(1_000_000 / mired)}
    else
      %{}
    end
  end

  defp schedule_reconnect do
    Process.send_after(self(), :connect, 2_000)
  end

  defp clamp(value, min, max) when is_number(value) do
    value |> max(min) |> min(max)
  end

  defp to_number(value) when is_integer(value), do: value
  defp to_number(value) when is_float(value), do: value

  defp to_number(value) when is_binary(value) do
    case Float.parse(value) do
      {number, ""} -> number
      _ -> nil
    end
  end

  defp to_number(_value), do: nil

  defp load_group_light_ids(bridge_id) do
    Repo.all(
      from(gl in GroupLight,
        join: g in Group,
        on: g.id == gl.group_id,
        where: g.bridge_id == ^bridge_id and g.source == :hue,
        select: {gl.light_id, gl.group_id}
      )
    )
    |> Enum.reduce(%{}, fn {light_id, group_id}, acc ->
      Map.update(acc, light_id, [group_id], fn existing -> [group_id | existing] end)
    end)
  end

  defp load_group_lights(bridge_id) do
    Repo.all(
      from(gl in GroupLight,
        join: g in Group,
        on: g.id == gl.group_id,
        where: g.bridge_id == ^bridge_id and g.source == :hue,
        select: {gl.group_id, gl.light_id}
      )
    )
    |> Enum.reduce(%{}, fn {group_id, light_id}, acc ->
      Map.update(acc, group_id, [light_id], fn existing -> [light_id | existing] end)
    end)
  end

  defp maybe_update_groups_from_light(state, light_id, attrs) do
    if Map.has_key?(attrs, :kelvin) do
      group_ids = Map.get(state.group_light_ids, light_id, [])

      Enum.each(group_ids, fn group_id ->
        case Map.get(state.group_lights, group_id, []) do
          [] ->
            :ok

          member_ids ->
            case group_kelvin_average(member_ids, 50) do
              {:ok, avg_kelvin} ->
                State.put(:group, group_id, %{kelvin: avg_kelvin})

              :error ->
                :ok
            end
        end
      end)
    end
  end

  defp group_kelvin_average(member_ids, tolerance) do
    kelvins =
      member_ids
      |> Enum.map(fn member_id ->
        case State.get(:light, member_id) do
          %{kelvin: member_kelvin} when is_number(member_kelvin) -> member_kelvin
          _ -> nil
        end
      end)
      |> Enum.reject(&is_nil/1)

    if length(kelvins) == length(member_ids) do
      min_k = Enum.min(kelvins)
      max_k = Enum.max(kelvins)

      if max_k - min_k <= tolerance do
        avg = round(Enum.sum(kelvins) / length(kelvins))
        {:ok, avg}
      else
        :error
      end
    else
      :error
    end
  end
end
