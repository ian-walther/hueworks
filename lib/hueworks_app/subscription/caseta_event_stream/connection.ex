defmodule Hueworks.Subscription.CasetaEventStream.Connection do
  @moduledoc false

  use GenServer

  require Logger

  import Ecto.Query, only: [from: 2]

  alias Hueworks.Control.CasetaLeap
  alias Hueworks.Control.State
  alias Hueworks.Control.StateParser
  alias Hueworks.Picos
  alias Hueworks.Repo
  alias Hueworks.Schemas.{Light, PicoButton, PicoDevice}

  @refresh_interval_ms 2_000

  def start_link(bridge, opts \\ []) do
    if missing_credentials?(bridge) do
      {:error, :missing_credentials}
    else
      GenServer.start_link(__MODULE__, {bridge, opts}, [])
    end
  end

  @impl true
  def init({bridge, opts}) do
    connect_fun = Keyword.get(opts, :connect_fun, &connect/1)

    state = %{
      bridge: bridge,
      socket: nil,
      lights: %{},
      pico_button_ids: [],
      buffer: "",
      last_refresh_at: 0,
      connect_fun: connect_fun
    }

    {:ok, state, {:continue, :connect}}
  end

  def init(bridge), do: init({bridge, []})

  @impl true
  def handle_continue(:connect, state) do
    case state.connect_fun.(state.bridge) do
      {:ok, socket} ->
        :ssl.setopts(socket, active: false, packet: :line)

        state = %{
          state
          | socket: socket,
            lights: load_lights(state.bridge.id),
            pico_button_ids: load_pico_button_ids(state.bridge.id),
            buffer: ""
        }

        read_initial_zone_status(socket, state)

        subscribe(socket, "/zone/status")
        subscribe_button_events(state)
        :ssl.setopts(socket, active: :once, packet: :line)

        {:noreply, state}

      {:error, reason} ->
        Logger.warning("Caseta LEAP connection failed: #{inspect(reason)}")
        {:stop, reason, state}
    end
  end

  @impl true
  def handle_info({:ssl, socket, data}, state) do
    :ssl.setopts(socket, active: :once)
    handle_frame(data, state)
  end

  @impl true
  def handle_info({:ssl_closed, _socket}, state) do
    Logger.info("Caseta LEAP connection closed for #{state.bridge.name} (#{state.bridge.host})")
    {:stop, :normal, state}
  end

  @impl true
  def handle_info({:ssl_error, _socket, reason}, state) do
    Logger.warning("Caseta LEAP socket error: #{inspect(reason)}")
    {:stop, :normal, state}
  end

  def handle_frame(data, state) do
    payload =
      data
      |> IO.iodata_to_binary()
      |> String.trim()

    case decode_message(payload) do
      {:ok, %{"Body" => %{"ZoneStatus" => zone_status}}} ->
        {:noreply, handle_zone_status(zone_status, state)}

      {:ok, %{"Body" => %{"ButtonStatus" => button_status}} = message} ->
        state = handle_button_status(button_status, state)
        log_pico_event(button_status, message, state)
        {:noreply, state}

      {:ok, _message} ->
        {:noreply, state}

      {:error, _reason} ->
        {:noreply, state}
    end
  end

  defp handle_zone_status(zone_status, state) do
    zone_id = zone_status |> get_in(["Zone", "href"]) |> href_id("zone")
    level = zone_status["Level"]
    state = maybe_refresh_for_zone(state, zone_id)

    case Map.get(state.lights, to_string(zone_id)) do
      nil ->
        state

      light_id ->
        update =
          %{}
          |> Map.merge(StateParser.brightness_from_0_100(level))
          |> Map.merge(StateParser.power_from_level(level))

        state_put(state, :light, light_id, update)
        state
    end
  end

  defp log_pico_event(button_status, message, state) do
    button_id = button_status |> get_in(["Button", "href"]) |> href_id("button")
    event_type = button_status["EventType"]

    Logger.info(
      "[pico-trace] caseta_button_event bridge_id=#{state.bridge.id} button_id=#{inspect(button_id)} event_type=#{inspect(event_type)} payload=#{inspect(button_status)} message=#{inspect(message)}"
    )
  end

  defp handle_button_status(button_status, state) do
    button_id = button_status |> get_in(["Button", "href"]) |> href_id("button")
    event_type = button_status["EventType"] || get_in(button_status, ["ButtonEvent", "EventType"])

    cond do
      not is_binary(button_id) ->
        Logger.warning(
          "[pico-trace] caseta_button_event_ignored bridge_id=#{state.bridge.id} reason=:missing_button_id payload=#{inspect(button_status)}"
        )

        state

      event_type != "Press" ->
        Logger.info(
          "[pico-trace] caseta_button_event_ignored bridge_id=#{state.bridge.id} button_id=#{inspect(button_id)} reason=:unsupported_event_type event_type=#{inspect(event_type)}"
        )

        state

      true ->
        state = maybe_refresh_for_button(state, button_id)
        result = handle_pico_button_press(state.bridge.id, button_id)

        Logger.info(
          "[pico-trace] caseta_button_event_handled bridge_id=#{state.bridge.id} button_id=#{inspect(button_id)} result=#{inspect(result)}"
        )

        state
    end
  end

  defp handle_pico_button_press(bridge_id, button_id) do
    Picos.handle_button_press(bridge_id, button_id)
  rescue
    exception ->
      Logger.error(
        "[pico-trace] caseta_button_event_failed bridge_id=#{bridge_id} button_id=#{inspect(button_id)} exception=#{Exception.format(:error, exception, __STACKTRACE__)}"
      )

      {:error, exception}
  end

  defp read_initial_zone_status(socket, state) do
    request =
      %{
        "CommuniqueType" => "ReadRequest",
        "Header" => %{"Url" => "/zone/status"}
      }

    with :ok <- CasetaLeap.send_request(:ssl, socket, request),
         {:ok, decoded} <- read_until_match(socket, "/zone/status", 5000) do
      decoded
      |> zone_status_list()
      |> Enum.each(&handle_zone_status(&1, state))
    else
      {:error, reason} ->
        Logger.warning("Caseta LEAP initial zone status failed: #{inspect(reason)}")

      other ->
        Logger.warning("Caseta LEAP initial zone status failed: #{inspect(other)}")
    end
  end

  defp subscribe(socket, url) do
    CasetaLeap.send_request(:ssl, socket, %{
      "CommuniqueType" => "SubscribeRequest",
      "Header" => %{"Url" => url}
    })
  end

  defp subscribe_button_events(state) do
    button_ids = Map.get(state, :pico_button_ids, [])

    Logger.info(
      "[pico-trace] caseta_button_subscribe_start bridge_id=#{state.bridge.id} button_count=#{length(button_ids)} button_ids=#{inspect(button_ids)}"
    )

    Enum.each(button_ids, fn button_id ->
      subscribe_url(state, "/button/#{button_id}/status/event")
    end)
  end

  defp subscribe_new_button_events(state, old_button_ids) do
    old_button_ids = MapSet.new(old_button_ids)

    state
    |> Map.get(:pico_button_ids, [])
    |> Enum.reject(&MapSet.member?(old_button_ids, &1))
    |> Enum.each(fn button_id ->
      subscribe_url(state, "/button/#{button_id}/status/event")
    end)

    state
  end

  defp subscribe_url(state, url) do
    subscribe_fun = Map.get(state, :subscribe_fun, &subscribe/2)

    case Map.get(state, :socket) do
      nil -> :ok
      socket -> subscribe_fun.(socket, url)
    end
  end

  defp read_until_match(socket, url, timeout) do
    CasetaLeap.read_until_match(socket, url, timeout, :message)
  end

  defp decode_message(line) do
    CasetaLeap.decode_message(line)
  end

  defp load_lights(bridge_id) do
    Repo.all(
      from(l in Light,
        where: l.bridge_id == ^bridge_id and l.source == :caseta and l.enabled == true
      )
    )
    |> Enum.reduce(%{}, fn light, acc -> Map.put(acc, light.source_id, light.id) end)
  end

  defp load_pico_button_ids(bridge_id) do
    Repo.all(
      from(pb in PicoButton,
        join: pd in PicoDevice,
        on: pd.id == pb.pico_device_id,
        where: pd.bridge_id == ^bridge_id and pb.enabled == true,
        select: pb.source_id,
        order_by: [asc: pb.source_id]
      )
    )
    |> Enum.reject(&(&1 in [nil, ""]))
  end

  defp maybe_refresh_for_zone(state, zone_id) do
    if Map.has_key?(state.lights, to_string(zone_id)) do
      state
    else
      refresh_indexes_if_due(state)
    end
  end

  defp maybe_refresh_for_button(state, button_id) do
    if button_id in Map.get(state, :pico_button_ids, []) do
      state
    else
      refresh_indexes_if_due(state)
    end
  end

  defp refresh_indexes_if_due(state) do
    now = System.monotonic_time(:millisecond)
    last_refresh_at = Map.get(state, :last_refresh_at)

    if refresh_due?(now, last_refresh_at) do
      old_button_ids = Map.get(state, :pico_button_ids, [])

      state
      |> Map.merge(%{
        lights: load_lights(state.bridge.id),
        pico_button_ids: load_pico_button_ids(state.bridge.id),
        last_refresh_at: now
      })
      |> subscribe_new_button_events(old_button_ids)
    else
      state
    end
  end

  defp refresh_due?(_now, last_refresh_at) when last_refresh_at in [nil, 0], do: true
  defp refresh_due?(now, last_refresh_at), do: now - last_refresh_at > @refresh_interval_ms

  defp zone_status_list(%{"Body" => %{"ZoneStatus" => statuses}}) when is_list(statuses),
    do: statuses

  defp zone_status_list(%{"Body" => %{"ZoneStatus" => status}}) when is_map(status),
    do: [status]

  defp zone_status_list(%{"Body" => %{"ZoneStatuses" => statuses}}) when is_list(statuses),
    do: statuses

  defp zone_status_list(_decoded), do: []

  defp connect(bridge) do
    CasetaLeap.connect(bridge)
  end

  defp href_id(href, type) do
    case String.split(to_string(href || ""), "/", trim: true) do
      [^type, id] -> id
      _ -> nil
    end
  end

  defp missing_credentials?(bridge) do
    credentials = Hueworks.Schemas.Bridge.credentials_struct(bridge)

    Enum.any?(
      [credentials.cert_path, credentials.key_path, credentials.cacert_path],
      &CasetaLeap.invalid_credential?/1
    )
  end

  defp state_put(state, type, id, update) do
    putter = Map.get(state, :state_put, &State.put/3)
    putter.(type, id, update)
  end
end
