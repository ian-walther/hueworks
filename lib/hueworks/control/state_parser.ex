defmodule Hueworks.Control.StateParser do
  @moduledoc false

  alias Hueworks.Control.HomeAssistantPayload
  alias Hueworks.Kelvin
  alias Hueworks.Util

  def power_map(true), do: %{power: :on}
  def power_map(false), do: %{power: :off}
  def power_map("on"), do: %{power: :on}
  def power_map("off"), do: %{power: :off}
  def power_map("ON"), do: %{power: :on}
  def power_map("OFF"), do: %{power: :off}
  def power_map(_), do: %{}

  def power_from_level(level) when is_number(level) do
    %{power: if(level > 0, do: :on, else: :off)}
  end

  def power_from_level(_level), do: %{}

  def brightness_from_0_255(value) when is_number(value) do
    percent = round(value / 255 * 100)
    %{brightness: Util.normalize_percent(percent)}
  end

  def brightness_from_0_255(_value), do: %{}

  def brightness_from_0_100(value) when is_number(value) do
    %{brightness: Util.normalize_percent(value)}
  end

  def brightness_from_0_100(_value), do: %{}

  def brightness_from_z2m(value) when is_number(value) do
    percent =
      cond do
        value <= 1 -> round(value * 100)
        value <= 100 -> round(value)
        true -> round(value / 254 * 100)
      end

    %{brightness: Util.normalize_percent(percent, 0, 100)}
  end

  def brightness_from_z2m(_value), do: %{}

  def kelvin_from_mired(mired) when is_number(mired) and mired > 0 do
    %{kelvin: round(1_000_000 / mired)}
  end

  def kelvin_from_mired(_mired), do: %{}

  def kelvin_from_ha_attrs(attrs, entity) when is_map(attrs) do
    extended_xy_kelvin = extended_xy_kelvin(attrs, entity)

    cond do
      is_number(extended_xy_kelvin) ->
        %{kelvin: round(extended_xy_kelvin)}

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

  def kelvin_from_z2m_attrs(attrs, entity) when is_map(attrs) do
    extended_xy_kelvin = extended_xy_kelvin(attrs, entity)

    cond do
      is_number(extended_xy_kelvin) ->
        %{kelvin: round(extended_xy_kelvin)}

      is_number(attrs["color_temp_kelvin"]) ->
        kelvin = Kelvin.map_from_event(entity, round(attrs["color_temp_kelvin"]))
        %{kelvin: kelvin}

      is_number(attrs["color_temp"]) and attrs["color_temp"] > 0 and attrs["color_temp"] <= 1000 ->
        kelvin = round(1_000_000 / attrs["color_temp"])
        %{kelvin: Kelvin.map_from_event(entity, kelvin)}

      is_number(attrs["color_temp"]) and attrs["color_temp"] > 1000 ->
        kelvin = Kelvin.map_from_event(entity, round(attrs["color_temp"]))
        %{kelvin: kelvin}

      true ->
        %{}
    end
  end

  def kelvin_from_z2m_attrs(_attrs, _entity), do: %{}

  defp extended_xy_kelvin(attrs, entity) do
    if extended_kelvin_range_enabled?(entity) do
      case xy_from_attrs(attrs) do
        {x, y} when is_number(x) and is_number(y) -> inverse_extended_xy(x, y)
        _ -> nil
      end
    else
      nil
    end
  end

  defp xy_from_attrs(attrs) when is_map(attrs) do
    xy_color = attrs["xy_color"] || attrs[:xy_color]
    color = attrs["color"] || attrs[:color]

    cond do
      is_list(xy_color) and length(xy_color) == 2 ->
        [x, y] = xy_color

        if is_number(x) and is_number(y) do
          {x, y}
        else
          nil
        end

      true ->
        case color do
          %{"x" => x, "y" => y} when is_number(x) and is_number(y) -> {x, y}
          %{x: x, y: y} when is_number(x) and is_number(y) -> {x, y}
          _ -> nil
        end
    end
  end

  defp xy_from_attrs(_attrs), do: nil

  defp inverse_extended_xy(x, y) do
    Enum.min_by(2000..2700, fn kelvin ->
      {px, py} = HomeAssistantPayload.extended_xy(kelvin)
      :math.pow(px - x, 2) + :math.pow(py - y, 2)
    end)
  end

  defp extended_kelvin_range_enabled?(entity) when is_map(entity) do
    Map.get(entity, :extended_kelvin_range) == true or
      Map.get(entity, "extended_kelvin_range") == true
  end

  defp extended_kelvin_range_enabled?(_entity), do: false
end
