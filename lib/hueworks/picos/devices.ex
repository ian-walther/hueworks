defmodule Hueworks.Picos.Devices do
  @moduledoc false

  import Ecto.Query, only: [from: 2]

  alias Hueworks.Repo
  alias Hueworks.Schemas.{PicoButton, PicoDevice}
  alias Hueworks.Util

  def list_for_bridge(bridge_id) when is_integer(bridge_id) do
    Repo.all(
      from(pd in PicoDevice,
        where: pd.bridge_id == ^bridge_id
      )
    )
    |> Repo.preload([:area, buttons: from(pb in PicoButton, order_by: [asc: pb.button_number])])
    |> Enum.sort_by(fn device ->
      {Util.display_name(device) |> String.downcase(), device.id}
    end)
  end

  def get(id) when is_integer(id) do
    PicoDevice
    |> Repo.get(id)
    |> case do
      nil ->
        nil

      device ->
        Repo.preload(device, [
          :area,
          buttons: from(pb in PicoButton, order_by: [asc: pb.button_number])
        ])
    end
  end

  def set_area(%PicoDevice{} = device, area_id) do
    detected_area_id = auto_detected_area_id(device)
    area_id = Util.parse_optional_integer(area_id)
    metadata = device.metadata || %{}

    attrs =
      case area_id do
        nil ->
          %{
            area_id: detected_area_id,
            metadata:
              metadata
              |> Map.put("area_override", false)
          }

        area_id ->
          %{
            area_id: area_id,
            metadata:
              metadata
              |> Map.put("area_override", true)
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

  def update_display_name(%PicoDevice{} = device, attrs) when is_map(attrs) do
    attrs =
      attrs
      |> Map.update(:display_name, nil, &Util.normalize_display_name/1)

    device
    |> PicoDevice.changeset(attrs)
    |> Repo.update()
    |> case do
      {:ok, updated} -> {:ok, get(updated.id)}
      other -> other
    end
  end

  def update_display_name(%PicoDevice{} = device, display_name) do
    update_display_name(device, %{display_name: display_name})
  end

  def area_override?(%PicoDevice{} = device) do
    Map.get(device.metadata || %{}, "area_override") == true
  end

  def auto_detected_area_id(%PicoDevice{} = device) do
    (device.metadata || %{})
    |> Map.get("detected_area_id")
    |> Util.parse_optional_integer()
  end
end
