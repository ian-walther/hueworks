defmodule Hueworks.Picos.Sync do
  @moduledoc false

  import Ecto.Query, only: [from: 2]

  alias Hueworks.Import.Fetch.Caseta
  alias Hueworks.Picos
  alias Hueworks.Repo
  alias Hueworks.Schemas.{Bridge, Light, PicoButton, PicoDevice}

  def sync_bridge_picos(%Bridge{type: :caseta} = bridge) do
    raw = caseta_fetch_module().fetch_for_bridge(bridge)
    sync_bridge_picos(bridge, raw)
  rescue
    error -> {:error, Exception.message(error)}
  end

  def sync_bridge_picos(%Bridge{} = bridge, raw) when is_map(raw) do
    pico_buttons = Map.get(raw, :pico_buttons) || Map.get(raw, "pico_buttons") || []
    lights = Map.get(raw, :lights) || Map.get(raw, "lights") || []

    room_by_area_id = room_ids_by_area_id(bridge.id, lights)

    grouped =
      Enum.group_by(
        pico_buttons,
        &to_string(Map.get(&1, :parent_device_id) || Map.get(&1, "parent_device_id"))
      )

    Repo.transaction(fn ->
      existing_devices =
        Repo.all(from(pd in PicoDevice, where: pd.bridge_id == ^bridge.id))
        |> Map.new(&{&1.source_id, &1})

      seen_device_ids =
        Enum.reduce(grouped, MapSet.new(), fn {device_source_id, buttons}, seen ->
          if device_source_id in [nil, ""] do
            seen
          else
            device =
              upsert_device(
                bridge,
                existing_devices[device_source_id],
                device_source_id,
                buttons,
                room_by_area_id
              )

            upsert_buttons(device, buttons)
            MapSet.put(seen, device_source_id)
          end
        end)

      stale_ids =
        existing_devices
        |> Map.keys()
        |> Enum.reject(&MapSet.member?(seen_device_ids, &1))

      if stale_ids != [] do
        Repo.delete_all(
          from(pd in PicoDevice, where: pd.bridge_id == ^bridge.id and pd.source_id in ^stale_ids)
        )
      end

      :ok
    end)

    {:ok, Picos.list_devices_for_bridge(bridge.id)}
  end

  defp upsert_device(bridge, existing, source_id, buttons, room_by_area_id) do
    sample = List.first(buttons) || %{}
    area_id = normalize_source_id(Map.get(sample, :area_id) || Map.get(sample, "area_id"))
    detected_room_id = Map.get(room_by_area_id, area_id)
    hardware_profile = hardware_profile(buttons)
    name = Map.get(sample, :device_name) || Map.get(sample, "device_name") || "Pico"

    room_id =
      cond do
        existing && Picos.room_override?(existing) -> existing.room_id
        true -> detected_room_id
      end

    metadata =
      (if(existing, do: existing.metadata, else: %{}) || %{})
      |> Map.put("area_id", area_id)
      |> Map.put("detected_room_id", detected_room_id)
      |> Map.put_new("room_override", false)

    attrs = %{
      bridge_id: bridge.id,
      room_id: room_id,
      source_id: source_id,
      name: name,
      hardware_profile: hardware_profile,
      enabled: true,
      metadata: metadata
    }

    case existing do
      nil ->
        %PicoDevice{}
        |> PicoDevice.changeset(attrs)
        |> Repo.insert!()

      device ->
        device
        |> PicoDevice.changeset(attrs)
        |> Repo.update!()
    end
  end

  defp upsert_buttons(device, buttons) do
    existing_buttons =
      Repo.all(from(pb in PicoButton, where: pb.pico_device_id == ^device.id))
      |> Map.new(&{&1.source_id, &1})

    normalized_buttons =
      buttons
      |> Enum.map(fn button ->
        %{
          source_id:
            normalize_source_id(Map.get(button, :button_id) || Map.get(button, "button_id")),
          button_number:
            normalize_integer(Map.get(button, :button_number) || Map.get(button, "button_number"))
        }
      end)
      |> Enum.filter(fn button ->
        is_binary(button.source_id) and is_integer(button.button_number)
      end)
      |> Enum.sort_by(& &1.button_number)

    seen_button_ids =
      normalized_buttons
      |> Enum.with_index()
      |> Enum.reduce(MapSet.new(), fn {button, slot_index}, seen ->
        attrs = %{
          pico_device_id: device.id,
          source_id: button.source_id,
          button_number: button.button_number,
          slot_index: slot_index,
          enabled: true
        }

        case existing_buttons[button.source_id] do
          nil ->
            %PicoButton{}
            |> PicoButton.changeset(attrs)
            |> Repo.insert!()

          existing ->
            existing
            |> PicoButton.changeset(attrs)
            |> Repo.update!()
        end

        MapSet.put(seen, button.source_id)
      end)

    stale_ids =
      existing_buttons
      |> Map.keys()
      |> Enum.reject(&MapSet.member?(seen_button_ids, &1))

    if stale_ids != [] do
      Repo.delete_all(
        from(pb in PicoButton,
          where: pb.pico_device_id == ^device.id and pb.source_id in ^stale_ids
        )
      )
    end
  end

  defp room_ids_by_area_id(bridge_id, raw_lights) do
    room_id_by_zone_id =
      Repo.all(
        from(l in Light,
          where: l.bridge_id == ^bridge_id and l.source == :caseta,
          select: {l.source_id, l.room_id}
        )
      )
      |> Map.new()

    Enum.reduce(raw_lights, %{}, fn raw_light, acc ->
      zone_id = normalize_source_id(Map.get(raw_light, :zone_id) || Map.get(raw_light, "zone_id"))
      area_id = normalize_source_id(Map.get(raw_light, :area_id) || Map.get(raw_light, "area_id"))
      room_id = Map.get(room_id_by_zone_id, zone_id)

      if is_binary(area_id) and is_integer(room_id) do
        Map.put_new(acc, area_id, room_id)
      else
        acc
      end
    end)
  end

  defp hardware_profile(buttons) do
    case Enum.count(buttons) do
      5 -> "5_button"
      4 -> "4_button"
      2 -> "2_button"
      count -> "#{count}_button"
    end
  end

  defp normalize_integer(value) when is_integer(value), do: value
  defp normalize_integer(value) when is_float(value), do: round(value)

  defp normalize_integer(value) when is_binary(value) do
    case Integer.parse(value) do
      {parsed, ""} -> parsed
      _ -> nil
    end
  end

  defp normalize_integer(_value), do: nil

  defp normalize_source_id(value) when is_binary(value), do: value
  defp normalize_source_id(value) when is_integer(value), do: Integer.to_string(value)
  defp normalize_source_id(_value), do: nil

  defp caseta_fetch_module do
    Application.get_env(:hueworks, :caseta_pico_fetcher, Caseta)
  end
end
