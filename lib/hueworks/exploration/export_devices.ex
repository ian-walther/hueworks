defmodule Hueworks.Exploration.ExportDevices do
  @moduledoc """
  Export device information from Hue, Lutron, and Home Assistant for deduplication analysis.
  """

  @hue_bridges [
    %{
      name: "Upstairs Bridge",
      host: "192.168.1.162",
      api_key: "0GMTKdYDtkaPfKd6yS9hSOYek26dv-ChnDj4wohH"
    }
  ]

  @lutron_bridge_ip "192.168.1.123"
  @lutron_bridge_port 8081
  @lutron_cert_path "/Users/ianwalther/.config/pylutron_caseta/192.168.1.123.crt"
  @lutron_key_path "/Users/ianwalther/.config/pylutron_caseta/192.168.1.123.key"
  @lutron_cacert_path "/Users/ianwalther/.config/pylutron_caseta/192.168.1.123-bridge.crt"

  @ha_host "192.168.1.41"
  @ha_token "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiI1Y2MyNTVmZDU0OTE0ZWJmYjNmMjVjZGZmY2I2M2QxOSIsImlhdCI6MTc2ODQzNDc1NywiZXhwIjoyMDgzNzk0NzU3fQ.0Acp4FYb8GTxvC5G50dV4jwgbIWQedHP97zNM6_cJCE"

  @export_dir "exports"

  @doc """
  Export all device information from Hue, Lutron, and Home Assistant.

  Saves timestamped JSON files to #{@export_dir}/

  ## Example

      ExportDevices.export_all()
  """
  def export_all do
    timestamp = DateTime.utc_now() |> DateTime.to_iso8601(:basic) |> String.slice(0..14)

    File.mkdir_p!(@export_dir)

    IO.puts("\n=== Exporting Hue Devices ===")
    hue_data = export_hue()
    hue_file = Path.join(@export_dir, "hue_devices_#{timestamp}.json")
    write_json(hue_file, hue_data)
    IO.puts("Saved to: #{hue_file}")

    IO.puts("\n=== Exporting Lutron Devices ===")
    lutron_data = export_lutron()
    lutron_file = Path.join(@export_dir, "lutron_devices_#{timestamp}.json")
    write_json(lutron_file, lutron_data)
    IO.puts("Saved to: #{lutron_file}")

    IO.puts("\n=== Exporting Home Assistant Entities ===")
    ha_data = export_home_assistant()
    ha_file = Path.join(@export_dir, "ha_entities_#{timestamp}.json")
    write_json(ha_file, ha_data)
    IO.puts("Saved to: #{ha_file}")

    IO.puts("\n=== Export Complete ===")
    IO.puts("Files saved to: #{@export_dir}")

    %{
      hue_file: hue_file,
      lutron_file: lutron_file,
      ha_file: ha_file,
      timestamp: timestamp
    }
  end

  @doc """
  Export Hue device information (lights and groups).
  """
  def export_hue do
    bridges =
      Enum.map(@hue_bridges, fn bridge ->
        IO.puts("Fetching Hue lights from #{bridge.name}...")

        lights =
          fetch_hue_endpoint(bridge, "/lights")
          |> add_hue_macs()
          |> simplify_hue_lights()

        %{
          name: bridge.name,
          host: bridge.host,
          lights: lights
        }
      end)

    %{
      bridges: bridges,
      exported_at: DateTime.utc_now() |> DateTime.to_iso8601()
    }
  end

  @doc """
  Export Lutron device information (devices, zones, buttons).
  """
  def export_lutron do
    {:ok, socket} = connect_lutron()
    :ssl.setopts(socket, [{:active, false}, {:packet, :line}])

    IO.puts("Fetching Lutron devices...")
    devices = read_lutron_endpoint(socket, "/device")

    IO.puts("Fetching Lutron buttons...")
    buttons = read_lutron_endpoint(socket, "/button")

    lights = lutron_lights(devices)
    pico_buttons = lutron_buttons(devices, buttons)

    :ssl.close(socket)

    %{
      bridge_ip: @lutron_bridge_ip,
      lights: lights,
      pico_buttons: pico_buttons,
      exported_at: DateTime.utc_now() |> DateTime.to_iso8601()
    }
  end

  @doc """
  Export Home Assistant light entities (all states with full attributes).
  """
  def export_home_assistant do
    IO.puts("Connecting to Home Assistant...")
    {:ok, pid} = Hueworks.Exploration.HATest.connect(@ha_host, @ha_token)

    IO.puts("Fetching entity registry...")
    entity_registry = get_ha_entity_registry(pid)

    IO.puts("Fetching device registry...")
    device_registry = get_ha_device_registry(pid)

    # Filter to just lights for analysis (registry is config-based, not state)
    light_entities =
      entity_registry
      |> Enum.filter(fn entry ->
        String.starts_with?(entry["entity_id"], "light.")
      end)
      |> merge_entity_registry(entity_registry)
      |> merge_device_registry(device_registry)
      |> tag_entity_sources()
      |> simplify_ha_lights()

    %{
      host: @ha_host,
      light_entities: light_entities,
      light_count: length(light_entities),
      total_entity_count: length(entity_registry),
      exported_at: DateTime.utc_now() |> DateTime.to_iso8601()
    }
  end

  # Private helpers - Hue

  defp fetch_hue_endpoint(bridge, endpoint) do
    url = "http://#{bridge.host}/api/#{bridge.api_key}#{endpoint}"

    case HTTPoison.get(url, [], recv_timeout: 10_000) do
      {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
        case Jason.decode(body) do
          {:ok, data} -> data
          {:error, _reason} -> %{error: "Failed to decode JSON"}
        end

      {:ok, %HTTPoison.Response{status_code: status_code}} ->
        %{error: "HTTP #{status_code}"}

      {:error, %HTTPoison.Error{reason: reason}} ->
        %{error: inspect(reason)}
    end
  end

  defp add_hue_macs(lights) when is_map(lights) do
    Map.new(lights, fn {id, light} ->
      mac = hue_uniqueid_to_mac(light["uniqueid"])
      {id, Map.put(light, "mac", mac)}
    end)
  end

  defp add_hue_macs(lights), do: lights

  defp hue_uniqueid_to_mac(uniqueid) when is_binary(uniqueid) do
    uniqueid
    |> String.split("-", parts: 2)
    |> List.first()
  end

  defp hue_uniqueid_to_mac(_uniqueid), do: nil

  defp simplify_hue_lights(lights) when is_map(lights) do
    Map.new(lights, fn {id, light} ->
      control = get_in(light, ["capabilities", "control"]) || %{}
      state = light["state"] || %{}

      supports_brightness = Map.has_key?(state, "bri")
      supports_color = Map.has_key?(control, "colorgamut") or Map.has_key?(control, "colorgamuttype")
      supports_color_temp = Map.has_key?(control, "ct")

      {id,
       %{
         id: id,
         name: light["name"],
         uniqueid: light["uniqueid"],
         mac: light["mac"],
         modelid: light["modelid"],
         productname: light["productname"],
         type: light["type"],
         capabilities: %{
           brightness: supports_brightness,
           color: supports_color,
           color_temp: supports_color_temp
         }
       }}
    end)
  end

  defp simplify_hue_lights(lights), do: lights

  # Private helpers - Lutron

  defp connect_lutron do
    ssl_opts = [
      certfile: @lutron_cert_path,
      keyfile: @lutron_key_path,
      cacertfile: @lutron_cacert_path,
      verify: :verify_none,
      versions: [:"tlsv1.2"]
    ]

    case :ssl.connect(
           String.to_charlist(@lutron_bridge_ip),
           @lutron_bridge_port,
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

  defp read_lutron_endpoint(socket, url, timeout \\ 5000) do
    read_lutron_endpoint(socket, url, timeout, nil, [])
  end

  defp read_lutron_endpoint(socket, url, timeout, paging, acc) do
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
          nil -> finalize_lutron_responses(responses)
          next -> read_lutron_endpoint(socket, url, timeout, next, responses)
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

  defp finalize_lutron_responses(responses) do
    bodies = responses |> Enum.map(& &1["Body"]) |> Enum.filter(&is_map/1)
    {list_key, merged_list} = merge_lutron_bodies(bodies)
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

  defp merge_lutron_bodies(bodies) do
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
          case decode_lutron_line(data) do
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

  defp decode_lutron_line(data) do
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

  # Private helpers - Home Assistant

  defp get_ha_entity_registry(pid) do
    case request_ha(pid, "config/entity_registry/list", %{}) do
      {:ok, entities} -> entities
      {:error, _reason} -> []
    end
  end

  defp get_ha_device_registry(pid) do
    case request_ha(pid, "config/device_registry/list", %{}) do
      {:ok, devices} -> devices
      {:error, _reason} -> []
    end
  end

  defp merge_entity_registry(light_entities, entity_registry) do
    registry_by_entity_id =
      entity_registry
      |> Enum.filter(&is_map/1)
      |> Map.new(fn entity -> {entity["entity_id"], entity} end)

    Enum.map(light_entities, fn entity ->
      registry_entry = Map.get(registry_by_entity_id, entity["entity_id"])
      Map.put(entity, "registry", registry_entry)
    end)
  end

  defp merge_device_registry(light_entities, device_registry) do
    devices_by_id =
      device_registry
      |> Enum.filter(&is_map/1)
      |> Map.new(fn device -> {device["id"], device} end)

    Enum.map(light_entities, fn entity ->
      device_id = entity["device_id"]
      device = if device_id, do: Map.get(devices_by_id, device_id), else: nil
      Map.put(entity, "device", device)
    end)
  end

  defp tag_entity_sources(light_entities) do
    Enum.map(light_entities, fn entity ->
      source =
        entity_source(
          get_in(entity, ["registry", "platform"]),
          entity["device"]
        )

      Map.put(entity, "source", source)
    end)
  end

  defp entity_source(platform, device) do
    case platform do
      "hue" -> "hue"
      "lutron_caseta" -> "lutron"
      _ -> source_from_device(device) || "unknown"
    end
  end

  defp source_from_device(device) do
    identifiers = device_identifiers(device)

    cond do
      Enum.any?(identifiers, &match?({"hue", _}, &1)) -> "hue"
      Enum.any?(identifiers, &match?({"lutron_caseta", _}, &1)) -> "lutron"
      true -> nil
    end
  end

  defp device_identifiers(%{"identifiers" => identifiers}) when is_list(identifiers) do
    Enum.map(identifiers, fn
      [domain, value] -> {domain, value}
      {domain, value} -> {domain, value}
      _ -> nil
    end)
    |> Enum.filter(& &1)
  end

  defp device_identifiers(_device) do
    []
  end

  defp simplify_ha_lights(light_entities) do
    Enum.map(light_entities, fn entity ->
      registry = entity["registry"] || %{}
      device = entity["device"]

      %{
        entity_id: entity["entity_id"],
        name: registry["name"] || registry["original_name"],
        unique_id: registry["unique_id"],
        platform: registry["platform"],
        device_id: entity["device_id"],
        source: entity["source"],
        device: simplify_ha_device(device)
      }
    end)
  end

  defp simplify_ha_device(device) when is_map(device) do
    %{
      id: device["id"],
      name: device["name"],
      manufacturer: device["manufacturer"],
      model: device["model"],
      identifiers: device["identifiers"],
      connections: device["connections"],
      via_device_id: device["via_device_id"]
    }
  end

  defp simplify_ha_device(_device), do: nil

  defp request_ha(pid, type, params) do
    ref = make_ref()

    WebSockex.cast(pid, {:request, ref, self(), type, params, & &1})

    receive do
      {:response, ^ref, result} -> result
    after
      10_000 -> {:error, :timeout}
    end
  end

  # Private helpers - File I/O

  defp write_json(file_path, data) do
    json = Jason.encode!(data, pretty: true)
    File.write!(file_path, json)
  end
end
