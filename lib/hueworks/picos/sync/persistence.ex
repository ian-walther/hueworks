defmodule Hueworks.Picos.Sync.Persistence do
  @moduledoc false

  import Ecto.Query, only: [from: 2]

  alias Hueworks.Picos.Devices
  alias Hueworks.Picos.Sync.Snapshot
  alias Hueworks.Repo
  alias Hueworks.Schemas.{Bridge, PicoButton, PicoDevice}

  def sync_devices(%Bridge{} = bridge, grouped_buttons, room_by_area_id)
      when is_map(grouped_buttons) and is_map(room_by_area_id) do
    existing_devices =
      Repo.all(from(pd in PicoDevice, where: pd.bridge_id == ^bridge.id))
      |> Map.new(&{&1.source_id, &1})

    seen_device_ids =
      Enum.reduce(grouped_buttons, MapSet.new(), fn {device_source_id, buttons}, seen ->
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
  end

  defp upsert_device(bridge, existing, source_id, buttons, room_by_area_id) do
    sample = List.first(buttons) || %{}
    area_id = Snapshot.normalize_source_id(Map.get(sample, :area_id) || Map.get(sample, "area_id"))
    detected_room_id = Map.get(room_by_area_id, area_id)
    hardware_profile = Snapshot.hardware_profile(buttons)
    name = Map.get(sample, :device_name) || Map.get(sample, "device_name") || "Pico"

    room_id =
      cond do
        existing && Devices.room_override?(existing) -> existing.room_id
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

    seen_button_ids =
      buttons
      |> Snapshot.normalized_buttons()
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
end
