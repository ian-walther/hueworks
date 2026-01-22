defmodule Hueworks.Import.Fetch.Caseta do
  @moduledoc """
  Fetch minimal Lutron Caseta data needed for import.
  """

  @bridge_port 8081

  import Ecto.Query, only: [from: 2]

  alias Hueworks.Schemas.Bridge
  alias Hueworks.Repo

  def fetch do
    bridge = load_bridge(:caseta)

    {:ok, socket} = connect(bridge)
    :ssl.setopts(socket, [{:active, false}, {:packet, :line}])

    IO.puts("Fetching Lutron devices...")
    devices = read_endpoint(socket, "/device")

    IO.puts("Fetching Lutron buttons...")
    buttons = read_endpoint(socket, "/button")

    IO.puts("Fetching Lutron virtual buttons...")
    virtual_buttons = read_endpoint(socket, "/virtualbutton")

    lights = lutron_lights(devices)
    pico_buttons = lutron_buttons(devices, buttons)
    groups = lutron_groups(virtual_buttons)

    :ssl.close(socket)

    %{
      bridge_ip: bridge.host,
      lights: lights,
      pico_buttons: pico_buttons,
      groups: groups,
      exported_at: DateTime.utc_now() |> DateTime.to_iso8601()
    }
  end

  def fetch_for_bridge(bridge) do
    {:ok, socket} = connect(bridge)
    :ssl.setopts(socket, [{:active, false}, {:packet, :line}])

    devices = read_endpoint(socket, "/device")
    buttons = read_endpoint(socket, "/button")
    virtual_buttons = read_endpoint(socket, "/virtualbutton")

    lights = lutron_lights(devices)
    pico_buttons = lutron_buttons(devices, buttons)
    groups = lutron_groups(virtual_buttons)

    :ssl.close(socket)

    %{
      bridge_ip: bridge.host,
      lights: lights,
      pico_buttons: pico_buttons,
      groups: groups
    }
  end

  defp connect(bridge) do
    cert_path = bridge.credentials["cert_path"]
    key_path = bridge.credentials["key_path"]
    cacert_path = bridge.credentials["cacert_path"]

    if Enum.any?([cert_path, key_path, cacert_path], &invalid_credential?/1) do
      raise "Missing Caseta TLS credentials for bridge #{bridge.name} (#{bridge.host})"
    end

    ssl_opts = [
      certfile: cert_path,
      keyfile: key_path,
      cacertfile: cacert_path,
      verify: :verify_none,
      versions: [:"tlsv1.2"]
    ]

    case :ssl.connect(
           String.to_charlist(bridge.host),
           @bridge_port,
           ssl_opts,
           5000
         ) do
      {:ok, socket} ->
        {:ok, socket}

      {:error, reason} ->
        IO.puts("Lutron connection failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp read_endpoint(socket, url, timeout \\ 5000) do
    read_endpoint(socket, url, timeout, nil, [])
  end

  defp read_endpoint(socket, url, timeout, paging, acc) do
    header =
      if paging do
        %{"Url" => url, "Paging" => paging}
      else
        %{"Url" => url}
      end

    message =
      Jason.encode!(%{
        "CommuniqueType" => "ReadRequest",
        "Header" => header
      })

    :ssl.send(socket, message <> "\r\n")

    case read_until_match(socket, fn decoded ->
           get_in(decoded, ["Header", "Url"]) == url and
             not is_nil(get_in(decoded, ["Header", "StatusCode"]))
         end, timeout) do
      {:ok, decoded} ->
        responses = acc ++ [decoded]

        case next_paging(decoded) do
          nil -> finalize_responses(responses)
          next -> read_endpoint(socket, url, timeout, next, responses)
        end

      {:error, reason} ->
        IO.puts("Failed to read #{url}: #{inspect(reason)}")
        %{error: inspect(reason), responses: acc}
    end
  end

  defp next_paging(decoded) do
    paging = get_in(decoded, ["Header", "Paging"]) || %{}
    start = paging["Start"]
    limit = paging["Limit"]
    total = paging["Total"]

    cond do
      is_integer(start) and is_integer(limit) and is_integer(total) and start + limit < total ->
        %{"Start" => start + limit, "Limit" => limit}

      true ->
        nil
    end
  end

  defp finalize_responses(responses) do
    bodies = responses |> Enum.map(& &1["Body"]) |> Enum.filter(&is_map/1)
    {list_key, merged_list} = merge_bodies(bodies)
    base_body = List.first(bodies) || %{}

    %{
      responses: responses,
      merged_body:
        if list_key do
          Map.put(base_body, list_key, merged_list)
        else
          base_body
        end,
      merged_list_key: list_key
    }
  end

  defp merge_bodies(bodies) do
    list_keys =
      bodies
      |> Enum.map(&find_list_key/1)

    case Enum.uniq(list_keys) do
      [list_key] when not is_nil(list_key) ->
        merged =
          bodies
          |> Enum.flat_map(fn body -> Map.get(body, list_key, []) end)

        {list_key, merged}

      _ ->
        {nil, []}
    end
  end

  defp find_list_key(body) do
    body
    |> Enum.find_value(fn {key, value} ->
      if is_list(value), do: key, else: nil
    end)
  end

  defp read_until_match(socket, predicate, timeout) do
    deadline = System.monotonic_time(:millisecond) + timeout
    do_read_until_match(socket, predicate, deadline)
  end

  defp do_read_until_match(socket, predicate, deadline) do
    remaining = max(0, deadline - System.monotonic_time(:millisecond))

    if remaining == 0 do
      {:error, :timeout}
    else
      case :ssl.recv(socket, 0, remaining) do
        {:ok, data} ->
          case decode_line(data) do
            {:ok, decoded} ->
              if predicate.(decoded) do
                {:ok, decoded}
              else
                do_read_until_match(socket, predicate, deadline)
              end

            {:error, :invalid} ->
              do_read_until_match(socket, predicate, deadline)
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
          {:error, :invalid}
      end
    end
  end

  defp lutron_lights(devices) do
    device_list = get_in(devices, [:merged_body, "Devices"]) || []

    device_list
    |> Enum.filter(&is_list(&1["LocalZones"]))
    |> Enum.map(fn device ->
      zone_href = get_in(device, ["LocalZones", Access.at(0), "href"])
      area_href = get_in(device, ["AssociatedArea", "href"])

      %{
        device_id: href_id(device["href"], "device"),
        zone_id: href_id(zone_href, "zone"),
        name: lutron_device_name(device),
        area_id: href_id(area_href, "area"),
        type: device["DeviceType"],
        model: device["ModelNumber"],
        serial: device["SerialNumber"]
      }
    end)
    |> Enum.filter(& &1.zone_id)
  end

  defp lutron_buttons(devices, buttons) do
    device_list = get_in(devices, [:merged_body, "Devices"]) || []
    button_list = get_in(buttons, [:merged_body, "Buttons"]) || []

    button_group_devices =
      device_list
      |> Enum.filter(&is_list(&1["ButtonGroups"]))
      |> Enum.flat_map(fn device ->
        Enum.map(device["ButtonGroups"], fn group ->
          {href_id(group["href"], "buttongroup"), device}
        end)
      end)
      |> Enum.filter(fn {group_id, _device} -> group_id end)
      |> Map.new()

    button_list
    |> Enum.map(fn button ->
      parent_id = get_in(button, ["Parent", "href"]) |> href_id("buttongroup")
      device = button_group_devices[parent_id]
      area_href = get_in(device || %{}, ["AssociatedArea", "href"])

      %{
        button_id: href_id(button["href"], "button"),
        button_number: button["ButtonNumber"],
        parent_device_id: href_id(get_in(device || %{}, ["href"]), "device"),
        device_name: lutron_device_name(device || %{}),
        area_id: href_id(area_href, "area")
      }
    end)
    |> Enum.filter(& &1.button_id)
  end

  defp lutron_groups(virtual_buttons) do
    buttons = get_in(virtual_buttons, [:merged_body, "VirtualButtons"]) || []

    buttons
    |> Enum.filter(fn button -> button["IsProgrammed"] == true end)
    |> Enum.map(fn button ->
      %{
        group_id: href_id(button["href"], "virtualbutton"),
        name: button["Name"],
        type: "virtualbutton"
      }
    end)
    |> Enum.filter(& &1.group_id)
  end

  defp href_id(href, type) do
    case String.split(to_string(href || ""), "/", trim: true) do
      [^type, id] -> id
      _ -> nil
    end
  end

  defp lutron_device_name(device) do
    cond do
      is_list(device["FullyQualifiedName"]) ->
        Enum.join(device["FullyQualifiedName"], " / ")

      is_binary(device["Name"]) ->
        device["Name"]

      true ->
        "Unknown device"
    end
  end

  defp load_bridge(type) do
    case Repo.all(from(b in Bridge, where: b.type == ^type and b.enabled == true)) do
      [bridge] ->
        bridge

      [] ->
        raise "No enabled #{type} bridge found. Seed bridges before fetching."

      _ ->
        raise "Multiple enabled #{type} bridges found. Only one is supported for now."
    end
  end

  defp invalid_credential?(value) do
    not is_binary(value) or value == "" or value == "CHANGE_ME"
  end
end
