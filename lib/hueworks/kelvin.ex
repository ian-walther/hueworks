defmodule Hueworks.Kelvin do
  @moduledoc """
  Kelvin mapping helpers for translating between reported and actual ranges.
  """

  alias Hueworks.Util

  def mapping_supported?(entity) do
    source = get_field(entity, :source)
    source == :ha or source == "ha"
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
      {min(2000, min_kelvin), max_kelvin}
    else
      {min_kelvin, max_kelvin}
    end
  end

  def map_for_control(entity, kelvin) when is_number(kelvin) do
    map_between_ranges(kelvin, actual_range(entity), reported_range(entity))
  end

  def map_for_control(_entity, kelvin), do: kelvin

  def map_from_event(entity, kelvin) when is_number(kelvin) do
    map_between_ranges(kelvin, reported_range(entity), actual_range(entity))
  end

  def map_from_event(_entity, kelvin), do: kelvin

  defp map_between_ranges(value, {from_min, from_max}, {to_min, to_max})
       when is_number(from_min) and is_number(from_max) and is_number(to_min) and
              is_number(to_max) and from_max > from_min and to_max > to_min do
    ratio = (value - from_min) / (from_max - from_min)
    mapped = to_min + ratio * (to_max - to_min)
    round(Util.clamp(mapped, to_min, to_max))
  end

  defp map_between_ranges(value, _from_range, _to_range), do: value

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

  defp extended_kelvin_range?(entity) do
    get_field(entity, :extended_kelvin_range) == true
  end
end
