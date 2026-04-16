defmodule Hueworks.Picos.Devices do
  @moduledoc false

  import Ecto.Query, only: [from: 2]

  alias Hueworks.Repo
  alias Hueworks.Schemas.{PicoButton, PicoDevice}
  alias Hueworks.Util

  def list_for_bridge(bridge_id) when is_integer(bridge_id) do
    Repo.all(
      from(pd in PicoDevice,
        where: pd.bridge_id == ^bridge_id,
        order_by: [asc: pd.name]
      )
    )
    |> Repo.preload([:room, buttons: from(pb in PicoButton, order_by: [asc: pb.button_number])])
  end

  def get(id) when is_integer(id) do
    PicoDevice
    |> Repo.get(id)
    |> case do
      nil ->
        nil

      device ->
        Repo.preload(device, [
          :room,
          buttons: from(pb in PicoButton, order_by: [asc: pb.button_number])
        ])
    end
  end

  def set_room(%PicoDevice{} = device, room_id) do
    detected_room_id = auto_detected_room_id(device)
    room_id = Util.parse_optional_integer(room_id)
    metadata = device.metadata || %{}

    attrs =
      case room_id do
        nil ->
          %{
            room_id: detected_room_id,
            metadata:
              metadata
              |> Map.put("room_override", false)
          }

        room_id ->
          %{
            room_id: room_id,
            metadata:
              metadata
              |> Map.put("room_override", true)
          }
      end

    device
    |> PicoDevice.changeset(attrs)
    |> Repo.update()
    |> case do
      {:ok, updated} -> {:ok, get(updated.id)}
      other -> other
    end
  end

  def room_override?(%PicoDevice{} = device) do
    Map.get(device.metadata || %{}, "room_override") == true
  end

  def auto_detected_room_id(%PicoDevice{} = device) do
    (device.metadata || %{})
    |> Map.get("detected_room_id")
    |> Util.parse_optional_integer()
  end
end
