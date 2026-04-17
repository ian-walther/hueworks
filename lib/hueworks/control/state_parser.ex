defmodule Hueworks.Control.StateParser do
  @moduledoc false

  alias Hueworks.Color
  alias Hueworks.Kelvin
  alias Hueworks.Util

  @type state_map :: map()
  @type entity_map :: map()

  @spec home_assistant_state(state_map(), entity_map()) :: state_map()
  def home_assistant_state(state, entity) when is_map(state) do
    attrs = state["attributes"] || state[:attributes] || %{}
    raw_state = state["state"] || state[:state]

    %{}
    |> Map.merge(power_map(raw_state))
    |> Map.merge(brightness_from_0_255(attrs["brightness"] || attrs[:brightness]))
    |> Map.merge(kelvin_from_ha_attrs(attrs, entity))
    |> Map.merge(color_from_ha_attrs(attrs))
  end

  def home_assistant_state(_state, _entity), do: %{}

  @spec hue_event_state(state_map()) :: state_map()
  def hue_event_state(event) when is_map(event) do
    %{}
    |> Map.merge(power_map(get_in(event, ["on", "on"])))
    |> Map.merge(brightness_from_0_100(get_in(event, ["dimming", "brightness"])))
    |> Map.merge(kelvin_from_hue_event(event))
    |> Map.merge(color_from_hue_event(event))
  end

  def hue_event_state(_event), do: %{}

  @spec hue_v1_state(state_map(), atom() | String.t()) :: state_map()
  def hue_v1_state(resource, state_key) when is_map(resource) do
    attrs = resource[state_key] || resource[to_string(state_key)] || %{}

    %{}
    |> Map.merge(power_map(attrs["on"] || attrs[:on]))
    |> Map.merge(brightness_from_0_255(attrs["bri"] || attrs[:bri]))
    |> Map.merge(kelvin_from_mired(attrs["ct"] || attrs[:ct]))
    |> Map.merge(color_from_hue_v1_attrs(attrs))
  end

  def hue_v1_state(_resource, _state_key), do: %{}

  @spec z2m_state(state_map(), entity_map()) :: state_map()
  def z2m_state(payload, entity) when is_map(payload) do
    %{}
    |> Map.merge(
      power_map(payload["state"] || payload[:state] || payload["power"] || payload[:power])
    )
    |> Map.merge(brightness_from_z2m_attrs(payload))
    |> Map.merge(kelvin_from_z2m_attrs(payload, entity))
    |> Map.merge(color_from_z2m_attrs(payload))
  end

  def z2m_state(_payload, _entity), do: %{}

  @spec power_map(term()) :: state_map()
  def power_map(true), do: %{power: :on}
  def power_map(false), do: %{power: :off}
  def power_map("on"), do: %{power: :on}
  def power_map("off"), do: %{power: :off}
  def power_map("ON"), do: %{power: :on}
  def power_map("OFF"), do: %{power: :off}
  def power_map(_), do: %{}

  @spec power_from_level(number() | term()) :: state_map()
  def power_from_level(level) when is_number(level) do
    %{power: if(level > 0, do: :on, else: :off)}
  end

  def power_from_level(_level), do: %{}

  @spec brightness_from_0_255(number() | term()) :: state_map()
  def brightness_from_0_255(value) when is_number(value) do
    percent = round(value / 255 * 100)
    %{brightness: Util.normalize_percent(percent)}
  end

  def brightness_from_0_255(_value), do: %{}

  @spec brightness_from_0_100(number() | term()) :: state_map()
  def brightness_from_0_100(value) when is_number(value) do
    %{brightness: Util.normalize_percent(value)}
  end

  def brightness_from_0_100(_value), do: %{}

  @spec brightness_from_z2m(number() | term()) :: state_map()
  def brightness_from_z2m(value) when is_number(value) do
    percent =
      cond do
        value <= 1 -> round(value * 100)
        true -> round(value / 254 * 100)
      end

    %{brightness: Util.normalize_percent(percent, 0, 100)}
  end

  def brightness_from_z2m(_value), do: %{}

  @spec brightness_from_z2m_attrs(state_map()) :: state_map()
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

  @spec color_from_ha_attrs(state_map()) :: state_map()
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

  @spec color_from_z2m_attrs(state_map()) :: state_map()
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

  @spec color_from_hue_event(state_map()) :: state_map()
  def color_from_hue_event(event) when is_map(event) do
    case hue_xy_from_event(event) do
      {x, y} -> xy_map({x, y})
      _ -> %{}
    end
  end

  def color_from_hue_event(_event), do: %{}

  @spec color_from_hue_v1_attrs(state_map()) :: state_map()
  def color_from_hue_v1_attrs(attrs) when is_map(attrs) do
    xy = hue_xy_from_v1_attrs(attrs)
    color_mode = attrs["colormode"] || attrs[:colormode]

    cond do
      not is_tuple(xy) ->
        %{}

      color_mode in ["ct", :ct] ->
        %{}

      true ->
        xy_map(xy)
    end
  end

  def color_from_hue_v1_attrs(_attrs), do: %{}

  @spec kelvin_from_mired(number() | term()) :: state_map()
  def kelvin_from_mired(mired) when is_number(mired) and mired > 0 do
    %{kelvin: round(1_000_000 / mired)}
  end

  def kelvin_from_mired(_mired), do: %{}

  @spec kelvin_from_hue_event(state_map()) :: state_map()
  def kelvin_from_hue_event(event) when is_map(event) do
    mired =
      case event["color_temperature"] do
        %{"mirek" => value} -> Util.to_number(value)
        %{:mirek => value} -> Util.to_number(value)
        value -> Util.to_number(value)
      end

    kelvin_from_mired(mired)
  end

  def kelvin_from_hue_event(_event), do: %{}

  @spec kelvin_from_ha_attrs(state_map(), entity_map()) :: state_map()
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

  @spec kelvin_from_z2m_attrs(state_map(), entity_map()) :: state_map()
  def kelvin_from_z2m_attrs(attrs, entity) when is_map(attrs) do
    extended_xy_kelvin = raw_extended_xy_kelvin(attrs, entity)
    crossover_xy? = prefer_z2m_extended_xy_crossover?(attrs, entity, extended_xy_kelvin)

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
            if extended_xy_applicable?(attrs, entity) or crossover_xy? do
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

  defp parse_z2m_direct_kelvin(kelvin, attrs, entity) when is_number(kelvin) do
    case Kelvin.map_extended_reported_floor(entity, kelvin) do
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

  defp preserve_z2m_direct_low_kelvin?(attrs, entity, kelvin) when is_number(kelvin) do
    Kelvin.extended_low_kelvin?(entity, kelvin) and
      (z2m_color_mode(attrs) == "color_temp" or is_tuple(xy_from_attrs(attrs)))
  end

  defp prefer_z2m_extended_xy_crossover?(attrs, entity, extended_xy_kelvin)
       when is_number(extended_xy_kelvin) do
    direct_kelvin = z2m_direct_kelvin(attrs)
    extended_max = Kelvin.extended_boundary_kelvin(entity)
    extended_min = Kelvin.extended_min_kelvin(entity)
    crossover_floor = max(extended_min, extended_max - 100)
    mapped_direct = if is_number(direct_kelvin), do: Kelvin.map_from_event(entity, direct_kelvin)

    is_number(direct_kelvin) and is_number(mapped_direct) and mapped_direct > extended_max and
      extended_xy_kelvin >= crossover_floor and extended_xy_kelvin < extended_max
  end

  defp prefer_z2m_extended_xy_crossover?(_attrs, _entity, _extended_xy_kelvin), do: false

  defp extended_xy_kelvin(attrs, entity) do
    if extended_kelvin_range_enabled?(entity) and extended_xy_applicable?(attrs, entity) do
      raw_extended_xy_kelvin(attrs, entity)
    else
      nil
    end
  end

  defp raw_extended_xy_kelvin(attrs, entity) do
    if extended_kelvin_range_enabled?(entity) do
      case xy_from_attrs(attrs) do
        {x, y} when is_number(x) and is_number(y) -> Kelvin.inverse_extended_xy(entity, x, y)
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

  defp hue_xy_from_event(event) when is_map(event) do
    case event["color"] || event[:color] do
      %{"xy" => %{"x" => x, "y" => y}} when is_number(x) and is_number(y) -> {x, y}
      %{xy: %{x: x, y: y}} when is_number(x) and is_number(y) -> {x, y}
      %{"x" => x, "y" => y} when is_number(x) and is_number(y) -> {x, y}
      %{x: x, y: y} when is_number(x) and is_number(y) -> {x, y}
      _ -> nil
    end
  end

  defp hue_xy_from_v1_attrs(attrs) when is_map(attrs) do
    case attrs["xy"] || attrs[:xy] do
      [x, y] when is_number(x) and is_number(y) -> {x, y}
      _ -> nil
    end
  end

  # Some integrations include xy color coordinates alongside ordinary
  # white-temperature reports. Only treat xy as the source of truth when the
  # event is clearly in the extended low-end band; otherwise we'd incorrectly
  # remap normal whites back into the logical extended band.
  defp extended_xy_applicable?(attrs, entity) when is_map(attrs) do
    boundary = Kelvin.extended_boundary_kelvin(entity)

    cond do
      is_number(attrs["color_temp_kelvin"]) ->
        attrs["color_temp_kelvin"] < boundary

      is_number(attrs["color_temp"]) and attrs["color_temp"] > 0 and attrs["color_temp"] <= 1000 ->
        round(1_000_000 / attrs["color_temp"]) < boundary

      is_number(attrs["color_temp"]) and attrs["color_temp"] > 1000 ->
        attrs["color_temp"] < boundary

      true ->
        true
    end
  end

  defp parse_low_extended_kelvin(kelvin, entity) when is_number(kelvin) do
    case Kelvin.map_extended_reported_floor(entity, kelvin) do
      mapped when is_number(mapped) -> %{kelvin: mapped}
      nil -> %{kelvin: Kelvin.map_from_event(entity, kelvin)}
    end
  end

  defp extended_kelvin_range_enabled?(entity) when is_map(entity) do
    Map.get(entity, :extended_kelvin_range) == true or
      Map.get(entity, "extended_kelvin_range") == true
  end

  defp extended_kelvin_range_enabled?(_entity), do: false

  defp z2m_color_mode(attrs) when is_map(attrs) do
    mode = attrs["color_mode"] || attrs[:color_mode]
    if is_binary(mode), do: mode, else: nil
  end

  defp ha_color_mode(attrs) when is_map(attrs) do
    mode = attrs["color_mode"] || attrs[:color_mode]
    if is_binary(mode), do: mode, else: nil
  end

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

  defp has_any_temp_attrs?(attrs) when is_map(attrs) do
    is_number(attrs["color_temp"]) or is_number(attrs[:color_temp]) or
      is_number(attrs["color_temp_kelvin"]) or is_number(attrs[:color_temp_kelvin])
  end

  defp xy_map({x, y}) do
    %{x: round_xy(x), y: round_xy(y)}
  end

  defp round_xy(value) when is_float(value), do: Float.round(value, 4)
  defp round_xy(value) when is_integer(value), do: (value * 1.0) |> Float.round(4)
  defp round_xy(value), do: value
end
