defmodule Hueworks.Picos.Sync.Snapshot do
  @moduledoc false

  import Ecto.Query, only: [from: 2]

  alias Hueworks.Repo
  alias Hueworks.Schemas.Light

  def pico_buttons(raw) when is_map(raw) do
    Map.get(raw, :pico_buttons) || Map.get(raw, "pico_buttons") || []
  end

  def pico_buttons(_raw), do: []

  def lights(raw) when is_map(raw) do
    Map.get(raw, :lights) || Map.get(raw, "lights") || []
  end

  def lights(_raw), do: []

  def group_buttons_by_device(pico_buttons) when is_list(pico_buttons) do
    Enum.group_by(
      pico_buttons,
      &to_string(Map.get(&1, :parent_device_id) || Map.get(&1, "parent_device_id"))
    )
  end

  def room_ids_by_area_id(bridge_id, raw_lights) when is_integer(bridge_id) and is_list(raw_lights) do
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

  def hardware_profile(buttons) when is_list(buttons) do
    case Enum.count(buttons) do
      5 -> "5_button"
      4 -> "4_button"
      2 -> "2_button"
      count -> "#{count}_button"
    end
  end

  def normalized_buttons(buttons) when is_list(buttons) do
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
  end

  def normalize_integer(value) when is_integer(value), do: value
  def normalize_integer(value) when is_float(value), do: round(value)

  def normalize_integer(value) when is_binary(value) do
    case Integer.parse(value) do
      {parsed, ""} -> parsed
      _ -> nil
    end
  end

  def normalize_integer(_value), do: nil

  def normalize_source_id(value) when is_binary(value), do: value
  def normalize_source_id(value) when is_integer(value), do: Integer.to_string(value)
  def normalize_source_id(_value), do: nil
end
