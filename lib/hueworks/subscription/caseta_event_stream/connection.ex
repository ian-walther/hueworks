defmodule Hueworks.Subscription.CasetaEventStream.Connection do
  @moduledoc false

  use GenServer

  require Logger

  import Ecto.Query, only: [from: 2]

  alias Hueworks.Control.State
  alias Hueworks.Repo
  alias Hueworks.Schemas.Light

  @bridge_port 8081

  def start_link(bridge) do
    GenServer.start_link(__MODULE__, bridge, [])
  end

  @impl true
  def init(bridge) do
    case connect(bridge) do
      {:ok, socket} ->
        :ssl.setopts(socket, active: :once, packet: :line)

        state = %{
          bridge: bridge,
          socket: socket,
          lights: load_lights(bridge.id),
          buffer: ""
        }

        subscribe(socket, "/zone/status")
        subscribe(socket, "/button/status/event")

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
    {:stop, :closed, state}
  end

  @impl true
  def handle_info({:ssl_error, _socket, reason}, state) do
    Logger.warning("Caseta LEAP socket error: #{inspect(reason)}")
    {:stop, reason, state}
  end

  defp handle_frame(data, state) do
    payload =
      data
      |> IO.iodata_to_binary()
      |> String.trim()

    case decode_message(payload) do
      {:ok, %{"Body" => %{"ZoneStatus" => zone_status}}} ->
        handle_zone_status(zone_status, state)
        {:noreply, state}

      {:ok, %{"Body" => %{"ButtonStatus" => button_status}} = message} ->
        log_pico_event(button_status, message)
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
          |> maybe_put_brightness(level)
          |> maybe_put_power(level)

        State.put(:light, light_id, update)
    end
  end

  defp log_pico_event(button_status, message) do
    Logger.info("Caseta pico event (stub): #{inspect(%{button: button_status, msg: message})}")
  end

  defp subscribe(socket, url) do
    message =
      Jason.encode!(%{
        "CommuniqueType" => "SubscribeRequest",
        "Header" => %{"Url" => url}
      })

    :ssl.send(socket, message <> "\r\n")
  end

  defp decode_message(""), do: {:error, :empty}

  defp decode_message(line) do
    case Jason.decode(line) do
      {:ok, decoded} -> {:ok, decoded}
      {:error, _reason} -> {:error, :invalid}
    end
  end

  defp load_lights(bridge_id) do
    Repo.all(from(l in Light, where: l.bridge_id == ^bridge_id and l.source == :caseta and l.enabled == true))
    |> Enum.reduce(%{}, fn light, acc -> Map.put(acc, light.source_id, light.id) end)
  end

  defp maybe_put_brightness(acc, level) when is_number(level) do
    Map.put(acc, :brightness, clamp(round(level), 1, 100))
  end

  defp maybe_put_brightness(acc, _level), do: acc

  defp maybe_put_power(acc, level) when is_number(level) do
    Map.put(acc, :power, if(level > 0, do: :on, else: :off))
  end

  defp maybe_put_power(acc, _level), do: acc

  defp clamp(value, min, max) when is_number(value) do
    value |> max(min) |> min(max)
  end

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
end
