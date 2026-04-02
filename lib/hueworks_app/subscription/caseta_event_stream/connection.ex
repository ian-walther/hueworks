defmodule Hueworks.Subscription.CasetaEventStream.Connection do
  @moduledoc false

  use GenServer

  require Logger

  import Ecto.Query, only: [from: 2]

  alias Hueworks.Control.State
  alias Hueworks.Control.StateParser
  alias Hueworks.Picos
  alias Hueworks.Repo
  alias Hueworks.Schemas.{Light, PicoButton, PicoDevice}

  @bridge_port 8081

  def start_link(bridge) do
    GenServer.start_link(__MODULE__, bridge, [])
  end

  @impl true
  def init(bridge) do
    case connect(bridge) do
      {:ok, socket} ->
        :ssl.setopts(socket, active: false, packet: :line)

        state = %{
          bridge: bridge,
          socket: socket,
          lights: load_lights(bridge.id),
          pico_button_ids: load_pico_button_ids(bridge.id),
          buffer: ""
        }

        read_initial_zone_status(socket, state)

        subscribe(socket, "/zone/status")
        subscribe_button_events(socket, state)
        :ssl.setopts(socket, active: :once, packet: :line)

        {:ok, state}

      {:error, reason} ->
        Logger.warning("Caseta LEAP connection failed: #{inspect(reason)}")
        {:stop, reason}
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
        handle_zone_status(zone_status, state)
        {:noreply, state}

      {:ok, %{"Body" => %{"ButtonStatus" => button_status}} = message} ->
        handle_button_status(button_status, state)
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

    case Map.get(state.lights, to_string(zone_id)) do
      nil ->
        :ok

      light_id ->
        update =
          %{}
          |> Map.merge(StateParser.brightness_from_0_100(level))
          |> Map.merge(StateParser.power_from_level(level))

        state_put(state, :light, light_id, update)
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

      event_type != "Press" ->
        Logger.info(
          "[pico-trace] caseta_button_event_ignored bridge_id=#{state.bridge.id} button_id=#{inspect(button_id)} reason=:unsupported_event_type event_type=#{inspect(event_type)}"
        )

      true ->
        result = Picos.handle_button_press(state.bridge.id, button_id)

        Logger.info(
          "[pico-trace] caseta_button_event_handled bridge_id=#{state.bridge.id} button_id=#{inspect(button_id)} result=#{inspect(result)}"
        )
    end

    :ok
  end

  defp read_initial_zone_status(socket, state) do
    message =
      Jason.encode!(%{
        "CommuniqueType" => "ReadRequest",
        "Header" => %{"Url" => "/zone/status"}
      })

    :ssl.send(socket, message <> "\r\n")

    case read_until_match(socket, "/zone/status", 5000) do
      {:ok, decoded} ->
        decoded
        |> zone_status_list()
        |> Enum.each(&handle_zone_status(&1, state))

      {:error, reason} ->
        Logger.warning("Caseta LEAP initial zone status failed: #{inspect(reason)}")
    end
  end

  defp subscribe(socket, url) do
    message =
      Jason.encode!(%{
        "CommuniqueType" => "SubscribeRequest",
        "Header" => %{"Url" => url}
      })

    :ssl.send(socket, message <> "\r\n")
  end

  defp subscribe_button_events(socket, state) do
    button_ids = Map.get(state, :pico_button_ids, [])

    Logger.info(
      "[pico-trace] caseta_button_subscribe_start bridge_id=#{state.bridge.id} button_count=#{length(button_ids)} button_ids=#{inspect(button_ids)}"
    )

    Enum.each(button_ids, fn button_id ->
      subscribe(socket, "/button/#{button_id}/status/event")
    end)
  end

  defp read_until_match(socket, url, timeout) do
    deadline = System.monotonic_time(:millisecond) + timeout
    do_read_until_match(socket, url, deadline)
  end

  defp do_read_until_match(socket, url, deadline) do
    remaining = max(0, deadline - System.monotonic_time(:millisecond))

    if remaining == 0 do
      {:error, :timeout}
    else
      case :ssl.recv(socket, 0, remaining) do
        {:ok, data} ->
          data
          |> IO.iodata_to_binary()
          |> String.split("\r\n", trim: true)
          |> Enum.find_value(:continue, fn line ->
            case decode_message(line) do
              {:ok, %{"Header" => %{"Url" => ^url}} = decoded} ->
                {:ok, decoded}

              _ ->
                :continue
            end
          end)
          |> case do
            :continue -> do_read_until_match(socket, url, deadline)
            other -> other
          end

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  defp decode_message(""), do: {:error, :empty}

  defp decode_message(line) do
    case Jason.decode(line) do
      {:ok, decoded} -> {:ok, decoded}
      {:error, _reason} -> {:error, :invalid}
    end
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

  defp zone_status_list(%{"Body" => %{"ZoneStatus" => statuses}}) when is_list(statuses),
    do: statuses

  defp zone_status_list(%{"Body" => %{"ZoneStatus" => status}}) when is_map(status),
    do: [status]

  defp zone_status_list(%{"Body" => %{"ZoneStatuses" => statuses}}) when is_list(statuses),
    do: statuses

  defp zone_status_list(_decoded), do: []

  defp connect(bridge) do
    cert_path = bridge.credentials["cert_path"]
    key_path = bridge.credentials["key_path"]
    cacert_path = bridge.credentials["cacert_path"]

    if Enum.any?([cert_path, key_path, cacert_path], &invalid_credential?/1) do
      {:error, :missing_credentials}
    else
      ssl_opts = [
        certfile: cert_path,
        keyfile: key_path,
        cacertfile: cacert_path,
        verify: :verify_none,
        versions: [:"tlsv1.2"]
      ]

      :ssl.connect(String.to_charlist(bridge.host), @bridge_port, ssl_opts, 5000)
    end
  end

  defp href_id(href, type) do
    case String.split(to_string(href || ""), "/", trim: true) do
      [^type, id] -> id
      _ -> nil
    end
  end

  defp invalid_credential?(value) do
    not is_binary(value) or value == "" or value == "CHANGE_ME"
  end

  defp state_put(state, type, id, update) do
    putter = Map.get(state, :state_put, &State.put/3)
    putter.(type, id, update)
  end
end
