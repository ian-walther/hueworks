defmodule Hueworks.Control.StateParser do
  @moduledoc false

  alias Hueworks.Color
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
        true -> round(value / 254 * 100)
      end

    %{brightness: Util.normalize_percent(percent, 0, 100)}
  end

  def brightness_from_z2m(_value), do: %{}

  def brightness_from_z2m_attrs(attrs) when is_map(attrs) do
    cond do
      is_number(attrs["brightness_percent"]) ->
        brightness_from_0_100(attrs["brightness_percent"])

      is_number(attrs["brightness"]) ->
        brightness_from_z2m(attrs["brightness"])

      true ->
        %{}
    end
  end

  def brightness_from_z2m_attrs(_attrs), do: %{}

  def color_from_ha_attrs(attrs) when is_map(attrs) do
    xy = xy_from_attrs(attrs)
    color_mode = ha_color_mode(attrs)

    cond do
      is_tuple(xy) and color_mode in ["xy", "hs", "rgb", "rgbw", "rgbww"] ->
        xy_map(xy)

      is_tuple(xy) and has_any_temp_attrs?(attrs) ->
        %{}

      is_tuple(xy) ->
        xy_map(xy)

      true ->
        %{}
    end
  end

  def color_from_ha_attrs(_attrs), do: %{}

  def color_from_z2m_attrs(attrs) when is_map(attrs) do
    xy = xy_from_attrs(attrs)

    cond do
      not is_tuple(xy) ->
        %{}

      has_any_temp_attrs?(attrs) ->
        %{}

      is_tuple(xy) and z2m_color_mode(attrs) in ["xy", "hs", "rgb", "rgbw", "rgbww"] ->
        xy_map(xy)

      is_tuple(xy) ->
        xy_map(xy)

      true ->
        %{}
    end
  end

  def color_from_z2m_attrs(_attrs), do: %{}

  def color_from_hue_event(event) when is_map(event) do
    case hue_xy_from_event(event) do
      {x, y} -> xy_map({x, y})
      _ -> %{}
    end
  end

  def color_from_hue_event(_event), do: %{}

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
        parse_low_extended_kelvin(round(attrs["color_temp_kelvin"]), entity)

      is_number(attrs["color_temp"]) and attrs["color_temp"] > 0 ->
        kelvin = round(1_000_000 / attrs["color_temp"])
        parse_low_extended_kelvin(kelvin, entity)

      true ->
        %{}
    end
  end

  def kelvin_from_ha_attrs(_attrs, _entity), do: %{}

  def kelvin_from_z2m_attrs(attrs, entity) when is_map(attrs) do
    extended_xy_kelvin = raw_extended_xy_kelvin(attrs, entity)
    crossover_xy? = prefer_z2m_extended_xy_crossover?(attrs, extended_xy_kelvin)

    case z2m_color_mode(attrs) do
      "xy" ->
        parse_xy_preferred_z2m(attrs, entity)

      "color_temp" when crossover_xy? ->
        %{kelvin: round(extended_xy_kelvin)}

      "color_temp" ->
        parse_z2m_color_temp(attrs, entity)

      _other ->
        cond do
          is_number(extended_xy_kelvin) ->
            if extended_xy_applicable?(attrs) or crossover_xy? do
              %{kelvin: round(extended_xy_kelvin)}
            else
              parse_z2m_color_temp(attrs, entity)
            end

          true ->
            parse_z2m_color_temp(attrs, entity)
        end
    end
  end

  def kelvin_from_z2m_attrs(_attrs, _entity), do: %{}

  defp parse_xy_preferred_z2m(attrs, entity) do
    case raw_extended_xy_kelvin(attrs, entity) do
      kelvin when is_number(kelvin) ->
        %{kelvin: round(kelvin)}

      _ ->
        parse_z2m_color_temp(attrs, entity)
    end
  end

  defp parse_z2m_color_temp(attrs, entity) when is_map(attrs) do
    cond do
      is_number(attrs["color_temp_kelvin"]) ->
        parse_z2m_direct_kelvin(round(attrs["color_temp_kelvin"]), attrs, entity)

      is_number(attrs["color_temp"]) and attrs["color_temp"] > 0 and attrs["color_temp"] <= 1000 ->
        kelvin = round(1_000_000 / attrs["color_temp"])
        parse_low_extended_kelvin(kelvin, entity)

      is_number(attrs["color_temp"]) and attrs["color_temp"] > 1000 ->
        parse_z2m_direct_kelvin(round(attrs["color_temp"]), attrs, entity)

      true ->
        %{}
    end
  end

  defp parse_z2m_color_temp(_attrs, _entity), do: %{}

  defp parse_z2m_direct_kelvin(kelvin, attrs, entity) when is_number(kelvin) do
    case map_extended_reported_floor(kelvin, entity) do
      mapped when is_number(mapped) ->
        %{kelvin: mapped}

      nil ->
        cond do
          preserve_z2m_direct_low_kelvin?(attrs, entity, kelvin) ->
            %{kelvin: kelvin}

          true ->
            %{kelvin: Kelvin.map_from_event(entity, kelvin)}
        end
    end
  end

  defp parse_z2m_direct_kelvin(_kelvin, _attrs, _entity), do: %{}

  defp preserve_z2m_direct_low_kelvin?(attrs, entity, kelvin) when is_number(kelvin) do
    extended_kelvin_range_enabled?(entity) and kelvin < 2700 and
      (z2m_color_mode(attrs) == "color_temp" or is_tuple(xy_from_attrs(attrs)))
  end

  defp preserve_z2m_direct_low_kelvin?(_attrs, _entity, _kelvin), do: false

  defp prefer_z2m_extended_xy_crossover?(attrs, extended_xy_kelvin)
       when is_number(extended_xy_kelvin) do
    direct_kelvin = z2m_direct_kelvin(attrs)

    is_number(direct_kelvin) and direct_kelvin > 2700 and direct_kelvin < 3800 and
      extended_xy_kelvin >= 2600 and extended_xy_kelvin < 2700
  end

  defp prefer_z2m_extended_xy_crossover?(_attrs, _extended_xy_kelvin), do: false

  defp extended_xy_kelvin(attrs, entity) do
    if extended_kelvin_range_enabled?(entity) and extended_xy_applicable?(attrs) do
      raw_extended_xy_kelvin(attrs, entity)
    else
      nil
    end
  end

  defp raw_extended_xy_kelvin(attrs, entity) do
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
    hs_color = attrs["hs_color"] || attrs[:hs_color]
    color = attrs["color"] || attrs[:color]

    cond do
      is_list(xy_color) and length(xy_color) == 2 ->
        [x, y] = xy_color

        if is_number(x) and is_number(y) do
          {x, y}
        else
          nil
        end

      is_list(hs_color) and length(hs_color) == 2 ->
        [hue, saturation] = hs_color
        Color.hs_to_xy(hue, saturation)

      true ->
        case color do
          %{"x" => x, "y" => y} when is_number(x) and is_number(y) -> {x, y}
          %{x: x, y: y} when is_number(x) and is_number(y) -> {x, y}
          _ -> nil
        end
    end
  end

  defp xy_from_attrs(_attrs), do: nil

  defp hue_xy_from_event(event) when is_map(event) do
    case event["color"] || event[:color] do
      %{"xy" => %{"x" => x, "y" => y}} when is_number(x) and is_number(y) -> {x, y}
      %{xy: %{x: x, y: y}} when is_number(x) and is_number(y) -> {x, y}
      %{"x" => x, "y" => y} when is_number(x) and is_number(y) -> {x, y}
      %{x: x, y: y} when is_number(x) and is_number(y) -> {x, y}
      _ -> nil
    end
  end

  defp hue_xy_from_event(_event), do: nil

  defp inverse_extended_xy(x, y) do
    Enum.min_by(2000..2700, fn kelvin ->
      {px, py} = HomeAssistantPayload.extended_xy(kelvin)
      :math.pow(px - x, 2) + :math.pow(py - y, 2)
    end)
  end

  # Some integrations include xy color coordinates alongside ordinary
  # white-temperature reports. Only treat xy as the source of truth when the
  # event is clearly in the extended low-end band; otherwise we'd incorrectly
  # remap normal >2700K whites back into 2000K-2700K.
  defp extended_xy_applicable?(attrs) when is_map(attrs) do
    cond do
      is_number(attrs["color_temp_kelvin"]) ->
        attrs["color_temp_kelvin"] < 2700

      is_number(attrs["color_temp"]) and attrs["color_temp"] > 0 and attrs["color_temp"] <= 1000 ->
        round(1_000_000 / attrs["color_temp"]) < 2700

      is_number(attrs["color_temp"]) and attrs["color_temp"] > 1000 ->
        attrs["color_temp"] < 2700

      true ->
        true
    end
  end

  defp extended_xy_applicable?(_attrs), do: false

  defp parse_low_extended_kelvin(kelvin, entity) when is_number(kelvin) do
    case map_extended_reported_floor(kelvin, entity) do
      mapped when is_number(mapped) -> %{kelvin: mapped}
      nil -> %{kelvin: Kelvin.map_from_event(entity, kelvin)}
    end
  end

  defp parse_low_extended_kelvin(_kelvin, _entity), do: %{}

  # Some extended-range devices only report their native low-end color_temp floor
  # on events, even after we drove them lower via XY color. Remap that reported
  # floor back into the logical 2000K-2700K band so the UI doesn't snap upward.
  defp map_extended_reported_floor(kelvin, entity) when is_number(kelvin) do
    reported_min = map_field(entity, :reported_min_kelvin)

    cond do
      not extended_kelvin_range_enabled?(entity) ->
        nil

      not is_number(reported_min) ->
        nil

      reported_min <= 2000 or reported_min >= 2700 ->
        nil

      kelvin > reported_min + 25 ->
        nil

      true ->
        ratio = (kelvin - reported_min) / (2700 - reported_min)
        mapped = 2000 + ratio * 700
        round(Util.clamp(mapped, 2000, 2700))
    end
  end

  defp map_extended_reported_floor(_kelvin, _entity), do: nil

  defp extended_kelvin_range_enabled?(entity) when is_map(entity) do
    Map.get(entity, :extended_kelvin_range) == true or
      Map.get(entity, "extended_kelvin_range") == true
  end

  defp extended_kelvin_range_enabled?(_entity), do: false

  defp z2m_color_mode(attrs) when is_map(attrs) do
    mode = attrs["color_mode"] || attrs[:color_mode]
    if is_binary(mode), do: mode, else: nil
  end

  defp z2m_color_mode(_attrs), do: nil

  defp ha_color_mode(attrs) when is_map(attrs) do
    mode = attrs["color_mode"] || attrs[:color_mode]
    if is_binary(mode), do: mode, else: nil
  end

  defp ha_color_mode(_attrs), do: nil

  defp z2m_direct_kelvin(attrs) when is_map(attrs) do
    cond do
      is_number(attrs["color_temp_kelvin"]) ->
        round(attrs["color_temp_kelvin"])

      is_number(attrs["color_temp"]) and attrs["color_temp"] > 0 and attrs["color_temp"] <= 1000 ->
        round(1_000_000 / attrs["color_temp"])

      is_number(attrs["color_temp"]) and attrs["color_temp"] > 1000 ->
        round(attrs["color_temp"])

      true ->
        nil
    end
  end

  defp z2m_direct_kelvin(_attrs), do: nil

  defp has_any_temp_attrs?(attrs) when is_map(attrs) do
    is_number(attrs["color_temp"]) or is_number(attrs[:color_temp]) or
      is_number(attrs["color_temp_kelvin"]) or is_number(attrs[:color_temp_kelvin])
  end

  defp has_any_temp_attrs?(_attrs), do: false

  defp xy_map({x, y}) do
    %{x: round_xy(x), y: round_xy(y)}
  end

  defp round_xy(value) when is_float(value), do: Float.round(value, 4)
  defp round_xy(value) when is_integer(value), do: (value * 1.0) |> Float.round(4)
  defp round_xy(value), do: value

  defp map_field(entity, key) when is_map(entity) do
    Map.get(entity, key) || Map.get(entity, Atom.to_string(key))
  end

  defp map_field(_entity, _key), do: nil
end
