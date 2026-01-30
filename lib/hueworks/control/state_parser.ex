defmodule Hueworks.Control.StateParser do
  @moduledoc false

  alias Hueworks.Kelvin
  alias Hueworks.Util

  def power_map(true), do: %{power: :on}
  def power_map(false), do: %{power: :off}
  def power_map("on"), do: %{power: :on}
  def power_map("off"), do: %{power: :off}
  def power_map(_), do: %{}

  def power_from_level(level) when is_number(level) do
    %{power: if(level > 0, do: :on, else: :off)}
  end

  def power_from_level(_level), do: %{}

  def brightness_from_0_255(value) when is_number(value) do
    percent = round(value / 255 * 100)
    %{brightness: Util.clamp(percent, 1, 100)}
  end

  def brightness_from_0_255(_value), do: %{}

  def brightness_from_0_100(value) when is_number(value) do
    %{brightness: Util.clamp(round(value), 1, 100)}
  end

  def brightness_from_0_100(_value), do: %{}

  def kelvin_from_mired(mired) when is_number(mired) and mired > 0 do
    %{kelvin: round(1_000_000 / mired)}
  end

  def kelvin_from_mired(_mired), do: %{}

  def kelvin_from_ha_attrs(attrs, entity) when is_map(attrs) do
    cond do
      is_number(attrs["color_temp_kelvin"]) ->
        kelvin = Kelvin.map_from_event(entity, round(attrs["color_temp_kelvin"]))
        %{kelvin: kelvin}

      is_number(attrs["color_temp"]) and attrs["color_temp"] > 0 ->
        kelvin = round(1_000_000 / attrs["color_temp"])
        %{kelvin: Kelvin.map_from_event(entity, kelvin)}

      true ->
        %{}
    end
  end

  def kelvin_from_ha_attrs(_attrs, _entity), do: %{}
end
