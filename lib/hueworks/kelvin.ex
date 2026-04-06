defmodule Hueworks.Kelvin do
  @moduledoc """
  Kelvin mapping helpers for translating between reported and actual ranges.
  """

  alias Hueworks.Color
  alias Hueworks.Util

  def mapping_supported?(entity) do
    source = get_field(entity, :source)
    source in [:ha, "ha", :z2m, "z2m"]
  end

  def derive_range(entity) do
    min_kelvin =
      get_field(entity, :actual_min_kelvin) ||
        get_field(entity, :reported_min_kelvin)

    max_kelvin =
      get_field(entity, :actual_max_kelvin) ||
        get_field(entity, :reported_max_kelvin)

    {min_kelvin, max_kelvin} =
      cond do
        is_number(min_kelvin) and is_number(max_kelvin) ->
          {round(min_kelvin), round(max_kelvin)}

        true ->
          case mired_range(entity) do
            {min_mired, max_mired} when min_mired > 0 and max_mired > 0 ->
              min_k = round(1_000_000 / max_mired)
              max_k = round(1_000_000 / min_mired)
              {min_k, max_k}

            _ ->
              {2000, 6500}
          end
      end

    if extended_kelvin_range?(entity) do
      {min(extended_min_kelvin(entity), min_kelvin), max_kelvin}
    else
      {min_kelvin, max_kelvin}
    end
  end

  def extended_range(entity) do
    if extended_kelvin_range?(entity) do
      min_kelvin = extended_min_kelvin(entity)
      max_kelvin = extended_boundary_kelvin(entity)

      if is_number(min_kelvin) and is_number(max_kelvin) and max_kelvin > min_kelvin do
        {round(min_kelvin), round(max_kelvin)}
      else
        nil
      end
    else
      nil
    end
  end

  def extended_min_kelvin(entity) do
    get_field(entity, :extended_min_kelvin)
    |> case do
      value when is_number(value) -> round(value)
      _ -> 2000
    end
  end

  def extended_boundary_kelvin(entity) do
    case get_field(entity, :actual_min_kelvin) do
      value when is_number(value) -> round(value)
      _ -> 2700
    end
  end

  def extended_low_kelvin?(entity, kelvin) when is_number(kelvin) do
    case extended_range(entity) do
      {min_kelvin, max_kelvin} -> kelvin >= min_kelvin and kelvin < max_kelvin
      _ -> false
    end
  end

  def extended_low_kelvin?(_entity, _kelvin), do: false

  def extended_xy(entity, kelvin) when is_number(kelvin) do
    case extended_range(entity) do
      {min_kelvin, max_kelvin} ->
        kelvin = Util.clamp(kelvin, min_kelvin, max_kelvin)
        span = max_kelvin - min_kelvin
        t_base = if span > 0, do: (kelvin - min_kelvin) / span, else: 0.0
        t = min(1.0, t_base + 0.25 * (1.0 - t_base))
        s = 4.0 * t * (1.0 - t)
        {x_start, y_start} = Color.kelvin_to_xy(min_kelvin) || {0.522, 0.405}
        {x_end, y_end} = Color.kelvin_to_xy(max_kelvin) || {0.459, 0.41}
        x = x_start + (x_end - x_start) * t
        y = y_start + (y_end - y_start) * t + 0.03 * s
        {Float.round(x, 6), Float.round(y, 6)}

      _ ->
        nil
    end
  end

  def extended_xy(_entity, _kelvin), do: nil

  def inverse_extended_xy(entity, x, y) when is_number(x) and is_number(y) do
    case extended_range(entity) do
      {min_kelvin, max_kelvin} ->
        Enum.min_by(min_kelvin..max_kelvin, fn kelvin ->
          case extended_xy(entity, kelvin) do
            {px, py} -> :math.pow(px - x, 2) + :math.pow(py - y, 2)
            _ -> :infinity
          end
        end)

      _ ->
        nil
    end
  end

  def inverse_extended_xy(_entity, _x, _y), do: nil

  def map_extended_reported_floor(entity, kelvin) when is_number(kelvin) do
    reported_min = get_field(entity, :reported_min_kelvin)
    logical_min = extended_min_kelvin(entity)
    logical_max = extended_boundary_kelvin(entity)

    cond do
      not extended_kelvin_range?(entity) ->
        nil

      not is_number(reported_min) ->
        nil

      reported_min <= logical_min or reported_min >= logical_max ->
        nil

      kelvin > reported_min + 25 ->
        nil

      true ->
        ratio = (kelvin - reported_min) / (logical_max - reported_min)
        mapped = logical_min + ratio * (logical_max - logical_min)
        round(Util.clamp(mapped, logical_min, logical_max))
    end
  end

  def map_extended_reported_floor(_entity, _kelvin), do: nil

  def map_for_control(entity, kelvin) when is_number(kelvin) do
    map_between_ranges_mired(kelvin, actual_range(entity), reported_range(entity))
  end

  def map_for_control(_entity, kelvin), do: kelvin

  def map_from_event(entity, kelvin) when is_number(kelvin) do
    map_between_ranges_mired(kelvin, reported_range(entity), actual_range(entity))
  end

  def map_from_event(_entity, kelvin), do: kelvin

  def same_temperature_step?(left, right) do
    equivalent_temperature?(left, right, mired_tolerance: 0)
  end

  def equivalent_temperature?(left, right, opts \\ []) do
    tolerance = Keyword.get(opts, :mired_tolerance, 0)

    case {mired_step(left), mired_step(right)} do
      {nil, _} -> left == right
      {_, nil} -> left == right
      {a, b} -> abs(a - b) <= tolerance
    end
  end

  def mired_step(value) do
    case Util.to_number(value) do
      kelvin when is_number(kelvin) and kelvin > 0 ->
        kelvin
        |> then(&(1_000_000 / &1))
        |> round()

      _ ->
        nil
    end
  end

  defp map_between_ranges_mired(value, {from_min, from_max}, {to_min, to_max})
       when is_number(from_min) and is_number(from_max) and is_number(to_min) and
              is_number(to_max) and from_max > from_min and to_max > to_min do
    from_min_mired = kelvin_to_mired(from_max)
    from_max_mired = kelvin_to_mired(from_min)
    to_min_mired = kelvin_to_mired(to_max)
    to_max_mired = kelvin_to_mired(to_min)
    value_mired = kelvin_to_mired(value)

    ratio = (value_mired - from_min_mired) / (from_max_mired - from_min_mired)
    mapped_mired = to_min_mired + ratio * (to_max_mired - to_min_mired)

    mapped_kelvin =
      mapped_mired
      |> then(&round(1_000_000 / &1))
      |> Util.clamp(to_min, to_max)

    round(mapped_kelvin)
  end

  defp map_between_ranges_mired(value, _from_range, _to_range), do: value

  defp actual_range(entity) do
    {get_field(entity, :actual_min_kelvin), get_field(entity, :actual_max_kelvin)}
  end

  defp reported_range(entity) do
    {get_field(entity, :reported_min_kelvin), get_field(entity, :reported_max_kelvin)}
  end

  defp mired_range(%{metadata: metadata}) when is_map(metadata) do
    capabilities = get_nested(metadata, "capabilities") || %{}
    control = get_nested(capabilities, "control") || %{}
    ct = get_nested(control, "ct") || %{}
    min_mired = get_nested(ct, "min")
    max_mired = get_nested(ct, "max")

    if is_number(min_mired) and is_number(max_mired) do
      {min_mired, max_mired}
    else
      nil
    end
  end

  defp mired_range(_entity), do: nil

  defp get_nested(map, key) when is_map(map) and is_binary(key) do
    Map.get(map, key) ||
      try do
        Map.get(map, String.to_existing_atom(key))
      rescue
        ArgumentError -> nil
      end
  end

  defp get_nested(map, key) when is_map(map) and is_atom(key) do
    Map.get(map, key)
  end

  defp get_nested(_map, _key), do: nil

  defp get_field(entity, key) when is_map(entity) do
    Map.get(entity, key) || Map.get(entity, Atom.to_string(key))
  end

  defp get_field(_entity, _key), do: nil

  defp kelvin_to_mired(kelvin) when is_number(kelvin) and kelvin > 0 do
    1_000_000 / kelvin
  end

  defp extended_kelvin_range?(entity) do
    get_field(entity, :extended_kelvin_range) == true
  end
end
