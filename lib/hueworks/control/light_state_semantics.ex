defmodule Hueworks.Control.LightStateSemantics do
  @moduledoc false

  alias Hueworks.Kelvin
  alias Hueworks.Util

  def diff_state(actual, desired, opts \\ [])

  def diff_state(actual, desired, opts) when is_map(actual) and is_map(desired) do
    desired
    |> Enum.reduce(%{}, fn {key, value}, acc ->
      if values_equal?(key, value, value_or_alias(actual, key), opts) do
        acc
      else
        Map.put(acc, key, value)
      end
    end)
  end

  def diff_state(_actual, desired, _opts) when is_map(desired), do: desired

  def diverging_keys(expected, actual, opts \\ [])

  def diverging_keys(expected, actual, opts) when is_map(expected) and is_map(actual) do
    expected
    |> Enum.reduce([], fn {key, expected_value}, acc ->
      if values_equal?(key, expected_value, value_or_alias(actual, key), opts) do
        acc
      else
        [key | acc]
      end
    end)
    |> Enum.reverse()
  end

  def diverging_keys(expected, _actual, _opts) when is_map(expected) do
    expected
    |> Map.keys()
  end

  def value_or_alias(state, key) when is_map(state) do
    key_aliases(key)
    |> Enum.find_value(fn alias_key ->
      Map.get(state, alias_key)
    end)
  end

  def value_or_alias(_state, _key), do: nil

  def key_aliases(:kelvin), do: [:kelvin, "kelvin", :temperature, "temperature"]
  def key_aliases("kelvin"), do: [:kelvin, "kelvin", :temperature, "temperature"]
  def key_aliases(:temperature), do: [:temperature, "temperature", :kelvin, "kelvin"]
  def key_aliases("temperature"), do: [:temperature, "temperature", :kelvin, "kelvin"]
  def key_aliases(:brightness), do: [:brightness, "brightness"]
  def key_aliases("brightness"), do: [:brightness, "brightness"]
  def key_aliases(:power), do: [:power, "power"]
  def key_aliases("power"), do: [:power, "power"]
  def key_aliases(key), do: [key]

  def values_equal?(key, desired, actual, opts \\ [])

  def values_equal?(_key, desired, actual, _opts) when desired == actual, do: true

  def values_equal?(key, desired, actual, opts) when key in [:brightness, "brightness"] do
    tolerance = Keyword.get(opts, :brightness_tolerance, 0)

    case {Util.to_number(desired), Util.to_number(actual)} do
      {nil, _} -> desired == actual
      {_, nil} -> desired == actual
      {a, b} -> abs(round(a) - round(b)) <= tolerance
    end
  end

  def values_equal?(key, desired, actual, opts)
      when key in [:kelvin, "kelvin", :temperature, "temperature"] do
    tolerance = Keyword.get(opts, :temperature_mired_tolerance, 0)
    Kelvin.equivalent_temperature?(desired, actual, mired_tolerance: tolerance)
  end

  def values_equal?(_key, desired, actual, _opts), do: desired == actual

  def effective_desired_for_light(desired, light) when is_map(desired) do
    case kelvin_value(desired) do
      nil ->
        desired

      kelvin ->
        if supports_temp?(light) do
          {min_kelvin, max_kelvin} = Kelvin.derive_range(light)
          clamped_kelvin = round(Util.clamp(kelvin, min_kelvin, max_kelvin))
          put_kelvin(desired, clamped_kelvin)
        else
          drop_kelvin(desired)
        end
    end
  end

  def effective_desired_for_light(desired, _light), do: desired

  def kelvin_value(desired) when is_map(desired) do
    desired
    |> Enum.find_value(fn
      {key, value} when key in [:kelvin, "kelvin", :temperature, "temperature"] ->
        Util.to_number(value)

      _ ->
        nil
    end)
    |> case do
      nil -> nil
      value -> round(value)
    end
  end

  def kelvin_value(_desired), do: nil

  def supports_temp?(light) when is_map(light) do
    Map.get(light, :supports_temp) == true or Map.get(light, "supports_temp") == true
  end

  def supports_temp?(_light), do: false

  def drop_kelvin(desired) when is_map(desired) do
    desired
    |> Map.delete(:kelvin)
    |> Map.delete("kelvin")
    |> Map.delete(:temperature)
    |> Map.delete("temperature")
  end

  def drop_kelvin(desired), do: desired

  def put_kelvin(desired, clamped_kelvin) when is_map(desired) do
    keys =
      desired
      |> Map.keys()
      |> Enum.filter(&(&1 in [:kelvin, "kelvin", :temperature, "temperature"]))

    desired = drop_kelvin(desired)

    case keys do
      [] ->
        Map.put(desired, :kelvin, clamped_kelvin)

      _ ->
        Enum.reduce(keys, desired, fn key, acc ->
          Map.put(acc, key, clamped_kelvin)
        end)
    end
  end

  def put_kelvin(desired, _clamped_kelvin), do: desired
end
