defmodule Hueworks.Exploration.LutronTest do
  @moduledoc """
  Quick throwaway module to test Lutron LEAP button events.
  """

  @bridge_ip "192.168.1.123"
  @bridge_port 8081

  @cert_path "/Users/ianwalther/.config/pylutron_caseta/192.168.1.123.crt"
  @key_path "/Users/ianwalther/.config/pylutron_caseta/192.168.1.123.key"
  @cacert_path "/Users/ianwalther/.config/pylutron_caseta/192.168.1.123-bridge.crt"

  def connect do
    ssl_opts = [
      certfile: @cert_path,
      keyfile: @key_path,
      cacertfile: @cacert_path,
      verify: :verify_none,
      versions: [:"tlsv1.2"]
    ]

    case :ssl.connect(
           String.to_charlist(@bridge_ip),
           @bridge_port,
           ssl_opts,
           5000
         ) do
      {:ok, socket} ->
        IO.puts("Connected to Lutron bridge!")
        {:ok, socket}

      {:error, reason} ->
        IO.puts("Connection failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  def test_button_simple do
    {:ok, socket} = connect()

    Task.async(fn ->
      :ssl.setopts(socket, [{:active, false}, {:packet, :line}])

      IO.puts("\n=== READING DEVICES ===")
      devices = read_devices(socket)

      IO.puts("\n=== READING BUTTONS ===")
      buttons = read_buttons(socket)
      button_map = build_button_map(devices, buttons)

      subscribe_to_button_events(socket, Map.keys(button_map))

      IO.puts("\n=== DRAINING INITIAL RESPONSES ===")
      drain_initial(socket)

      IO.puts("\n=== NOW PRESS A PICO BUTTON ===\n")
      listen_decoded(socket, button_map)
    end)
    |> then(fn task ->
      IO.puts("Listening for button events...")
      {:ok, task}
    end)
  end

  def list_zone_devices do
    {:ok, socket} = connect()
    :ssl.setopts(socket, [{:active, false}, {:packet, :line}])

    IO.puts("\n=== ZONE DEVICES ===")
    devices = read_devices(socket)
    zone_devices = zone_devices(devices)

    Enum.each(zone_devices, fn device ->
      IO.puts("#{device.device_id} | zone #{device.zone_id} | #{device.name} (#{device.type})")
    end)

    :ssl.close(socket)
    :ok
  end

  def test_light_toggle(name_filter \\ nil) do
    {:ok, socket} = connect()
    :ssl.setopts(socket, [{:active, false}, {:packet, :line}])

    devices = read_devices(socket)
    zone_device = pick_zone_device(devices, name_filter)

    if zone_device do
      IO.puts("Toggling #{zone_device.name} (zone #{zone_device.zone_id})")
      set_zone_level(socket, zone_device.zone_id, 100)
      drain_for(socket, 1500)
      set_zone_level(socket, zone_device.zone_id, 0)
      drain_for(socket, 1500)
    else
      IO.puts("No matching zone device found.")
    end

    :ssl.close(socket)
    :ok
  end

  defp subscribe(socket, url) do
    message =
      Jason.encode!(%{
        "CommuniqueType" => "SubscribeRequest",
        "Header" => %{"Url" => url}
      })

    :ssl.send(socket, message <> "\r\n")
  end

  defp read_request(socket, url) do
    message =
      Jason.encode!(%{
        "CommuniqueType" => "ReadRequest",
        "Header" => %{"Url" => url}
      })

    :ssl.send(socket, message <> "\r\n")
  end

  defp read_devices(socket) do
    read_request(socket, "/device")

    case read_until(socket, fn decoded ->
           get_in(decoded, ["Header", "Url"]) == "/device" and
             is_list(get_in(decoded, ["Body", "Devices"]))
         end) do
      {:ok, decoded} ->
        get_in(decoded, ["Body", "Devices"]) || []

      {:error, reason} ->
        IO.puts("Failed to read /device list: #{inspect(reason)}")
        []
    end
  end

  defp read_buttons(socket) do
    read_request(socket, "/button")

    case read_until(socket, fn decoded ->
           get_in(decoded, ["Header", "Url"]) == "/button" and
             is_list(get_in(decoded, ["Body", "Buttons"]))
         end) do
      {:ok, decoded} ->
        get_in(decoded, ["Body", "Buttons"]) || []

      {:error, reason} ->
        IO.puts("Failed to read /button list: #{inspect(reason)}")
        []
    end
  end

  defp zone_devices(devices) do
    devices
    |> Enum.filter(&is_list(&1["LocalZones"]))
    |> Enum.map(fn device ->
      zone_href = get_in(device, ["LocalZones", Access.at(0), "href"])

      %{
        device_id: href_id(device["href"], "device"),
        zone_id: href_id(zone_href, "zone"),
        name: device_display_name(device),
        type: device["DeviceType"]
      }
    end)
    |> Enum.filter(& &1.zone_id)
  end

  defp pick_zone_device(devices, name_filter) do
    zone_devices = zone_devices(devices)

    case name_filter do
      nil ->
        List.first(zone_devices)

      filter ->
        downcased = String.downcase(filter)

        Enum.find(zone_devices, fn device ->
          String.contains?(String.downcase(device.name), downcased)
        end)
    end
  end

  defp set_zone_level(socket, zone_id, level) do
    message =
      Jason.encode!(%{
        "CommuniqueType" => "CreateRequest",
        "Header" => %{"Url" => "/zone/#{zone_id}/commandprocessor"},
        "Body" => %{
          "Command" => %{
            "CommandType" => "GoToLevel",
            "Parameter" => [
              %{"Type" => "Level", "Value" => level}
            ]
          }
        }
      })

    :ssl.send(socket, message <> "\r\n")
  end

  defp build_button_map(devices, buttons) do
    group_to_device =
      devices
      |> Enum.filter(&is_list(&1["ButtonGroups"]))
      |> Enum.flat_map(fn device ->
        Enum.map(device["ButtonGroups"], fn group ->
          {href_id(group["href"], "buttongroup"), device}
        end)
      end)
      |> Enum.filter(fn {group_id, _device} -> group_id end)
      |> Map.new()

    buttons
    |> Enum.map(fn button ->
      button_id = href_id(button["href"], "button")
      parent_id = get_in(button, ["Parent", "href"]) |> href_id("buttongroup")
      device = group_to_device[parent_id]

      device_name =
        cond do
          is_nil(device) ->
            "Unknown device"

          is_list(device["FullyQualifiedName"]) ->
            Enum.join(device["FullyQualifiedName"], " / ")

          is_binary(device["Name"]) ->
            device["Name"]

          true ->
            "Unknown device"
        end

      button_number = button["ButtonNumber"]

      {button_id,
       %{
         device_name: device_name,
         button_number: button_number
       }}
    end)
    |> Enum.filter(fn {button_id, _} -> is_binary(button_id) end)
    |> Map.new()
  end

  defp device_display_name(device) do
    cond do
      is_list(device["FullyQualifiedName"]) ->
        Enum.join(device["FullyQualifiedName"], " / ")

      is_binary(device["Name"]) ->
        device["Name"]

      true ->
        "Unknown device"
    end
  end

  defp subscribe_to_button_events(socket, button_ids) do
    Enum.each(button_ids, fn button_id ->
      subscribe(socket, "/button/#{button_id}/status/event")
      Process.sleep(50)
    end)
  end

  defp drain_initial(socket) do
    case :ssl.recv(socket, 0, 1000) do
      {:ok, data} ->
        log_decoded(data, %{})
        drain_initial(socket)

      {:error, :timeout} ->
        :ok

      {:error, reason} ->
        IO.puts("Error draining initial messages: #{inspect(reason)}")
        :ok
    end
  end

  defp drain_for(socket, duration_ms) do
    deadline = System.monotonic_time(:millisecond) + duration_ms

    do_drain_for(socket, deadline)
  end

  defp do_drain_for(socket, deadline) do
    remaining = max(0, deadline - System.monotonic_time(:millisecond))

    if remaining == 0 do
      :ok
    else
      case :ssl.recv(socket, 0, remaining) do
        {:ok, data} ->
          log_decoded(data, %{})
          do_drain_for(socket, deadline)

        {:error, :timeout} ->
          :ok

        {:error, reason} ->
          IO.puts("Error draining responses: #{inspect(reason)}")
          :ok
      end
    end
  end

  defp listen_decoded(socket, button_map) do
    case :ssl.recv(socket, 0, 10000) do
      {:ok, data} ->
        log_decoded(data, button_map)
        listen_decoded(socket, button_map)

      {:error, :timeout} ->
        IO.puts("Timeout, listening again...")
        listen_decoded(socket, button_map)

      {:error, reason} ->
        IO.puts("Error: #{inspect(reason)}")
    end
  end

  defp log_decoded(data, button_map) do
    case decode_line(data) do
      {:ok, decoded} ->
        case button_event(decoded, button_map) do
          {:ok, message} ->
            IO.puts(message)

          :ignore ->
            IO.inspect(decoded, label: "Received")
        end

      {:error, :invalid} ->
        :ok
    end
  end

  defp button_event(decoded, button_map) do
    event = get_in(decoded, ["Body", "ButtonStatus", "ButtonEvent", "EventType"])
    button_href = get_in(decoded, ["Body", "ButtonStatus", "Button", "href"])
    button_id = href_id(button_href, "button")

    if is_binary(event) and is_binary(button_id) do
      case Map.get(button_map, button_id) do
        %{device_name: device_name, button_number: button_number} ->
          suffix = if is_nil(button_number), do: "", else: " (button #{button_number})"
          {:ok, "Button event: #{device_name}#{suffix} #{event}"}

        nil ->
          {:ok, "Button event: button #{button_id} #{event}"}
      end
    else
      :ignore
    end
  end

  defp read_until(socket, predicate) do
    deadline = System.monotonic_time(:millisecond) + 5000

    do_read_until(socket, predicate, deadline)
  end

  defp do_read_until(socket, predicate, deadline) do
    remaining = max(0, deadline - System.monotonic_time(:millisecond))

    if remaining == 0 do
      {:error, :timeout}
    else
      case :ssl.recv(socket, 0, remaining) do
        {:ok, data} ->
          case decode_line(data) do
            {:ok, decoded} ->
              IO.inspect(decoded, label: "Received")

              if predicate.(decoded) do
                {:ok, decoded}
              else
                do_read_until(socket, predicate, deadline)
              end

            {:error, :invalid} ->
              do_read_until(socket, predicate, deadline)
          end

        {:error, :timeout} ->
          {:error, :timeout}

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  defp decode_line(data) do
    line =
      data
      |> IO.iodata_to_binary()
      |> String.trim()

    if line == "" do
      {:error, :invalid}
    else
      case Jason.decode(line) do
        {:ok, decoded} ->
          {:ok, decoded}

        {:error, _reason} ->
          IO.puts("Received (raw): #{line}")
          {:error, :invalid}
      end
    end
  end

  defp href_id(href, type) do
    case String.split(to_string(href || ""), "/", trim: true) do
      [^type, id] -> id
      _ -> nil
    end
  end

  def get_lights() do
    {:ok, socket} = connect()

    Task.async(fn ->
      :ssl.setopts(socket, [{:active, false}, {:packet, :line}])

      IO.puts("\n=== READING DEVICES ===")
      devices = read_devices(socket)
      devices |> dbg()

      IO.puts("\n=== READING BUTTONS ===")
      buttons = read_buttons(socket)
      button_map = build_button_map(devices, buttons)

      subscribe_to_button_events(socket, Map.keys(button_map))

      IO.puts("\n=== DRAINING INITIAL RESPONSES ===")
      drain_initial(socket)
    end)
    |> then(fn task ->
      Task.shutdown(task, :brutal_kill)
    end)
  end
end
