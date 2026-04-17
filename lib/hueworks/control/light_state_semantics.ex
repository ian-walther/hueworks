defmodule Hueworks.Control.LightStateSemantics do
  @moduledoc false

  alias Hueworks.Kelvin
  alias Hueworks.Util

  @type state_map :: map()
  @type comparison_opts :: keyword()
  @type xy_value :: float() | nil

  @spec diff_state(state_map(), state_map(), comparison_opts()) :: state_map()

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

  @spec diverging_keys(state_map(), state_map(), comparison_opts()) :: list(term())
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

  @spec value_or_alias(state_map(), term()) :: term() | nil
  def value_or_alias(state, key) when is_map(state) do
    key_aliases(key)
    |> Enum.find_value(fn alias_key ->
      if Map.has_key?(state, alias_key) do
        {:ok, Map.get(state, alias_key)}
      else
        nil
      end
    end)
    |> case do
      {:ok, value} -> value
      _ -> nil
    end
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
  def key_aliases(:x), do: [:x, "x"]
  def key_aliases("x"), do: [:x, "x"]
  def key_aliases(:y), do: [:y, "y"]
  def key_aliases("y"), do: [:y, "y"]
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

  def values_equal?(key, desired, actual, opts) when key in [:x, "x", :y, "y"] do
    tolerance = Keyword.get(opts, :xy_tolerance, 0.005)

    case {Util.to_number(desired), Util.to_number(actual)} do
      {nil, _} -> desired == actual
      {_, nil} -> desired == actual
      {a, b} -> abs(a - b) <= tolerance
    end
  end

  def values_equal?(_key, desired, actual, _opts), do: desired == actual

  @spec effective_desired_for_light(state_map(), state_map()) :: state_map()
  def effective_desired_for_light(desired, light) when is_map(desired) do
    desired
    |> maybe_clamp_kelvin(light)
    |> maybe_filter_xy(light)
  end

  def effective_desired_for_light(desired, _light), do: desired

  @spec x_value(state_map()) :: xy_value()
  def x_value(desired) when is_map(desired) do
    desired
    |> Enum.reduce_while(nil, fn
      {key, value}, _acc when key in [:x, "x"] -> {:halt, Util.to_number(value)}
      _entry, acc -> {:cont, acc}
    end)
    |> normalize_xy_value()
  end

  def x_value(_desired), do: nil

  @spec y_value(state_map()) :: xy_value()
  def y_value(desired) when is_map(desired) do
    desired
    |> Enum.reduce_while(nil, fn
      {key, value}, _acc when key in [:y, "y"] -> {:halt, Util.to_number(value)}
      _entry, acc -> {:cont, acc}
    end)
    |> normalize_xy_value()
  end

  def y_value(_desired), do: nil

  @spec kelvin_value(state_map()) :: integer() | nil
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

  @spec supports_temp?(state_map()) :: boolean()
  def supports_temp?(light) when is_map(light) do
    Map.get(light, :supports_temp) == true or Map.get(light, "supports_temp") == true
  end

  def supports_temp?(_light), do: false

  @spec supports_color?(state_map()) :: boolean()
  def supports_color?(light) when is_map(light) do
    Map.get(light, :supports_color) == true or Map.get(light, "supports_color") == true
  end

  def supports_color?(_light), do: false

  @spec drop_kelvin(state_map()) :: state_map()
  def drop_kelvin(desired) when is_map(desired) do
    desired
    |> Map.delete(:kelvin)
    |> Map.delete("kelvin")
    |> Map.delete(:temperature)
    |> Map.delete("temperature")
  end

  def drop_kelvin(desired), do: desired

  @spec drop_xy(state_map()) :: state_map()
  def drop_xy(desired) when is_map(desired) do
    desired
    |> Map.delete(:x)
    |> Map.delete("x")
    |> Map.delete(:y)
    |> Map.delete("y")
  end

  def drop_xy(desired), do: desired

  @spec put_kelvin(state_map(), integer()) :: state_map()
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

  @spec put_xy(state_map(), number(), number()) :: state_map()
  def put_xy(desired, x, y) when is_map(desired) do
    keys =
      desired
      |> Map.keys()
      |> Enum.filter(&(&1 in [:x, "x", :y, "y"]))

    desired = drop_xy(desired)

    case keys do
      [] ->
        desired
        |> Map.put(:x, x)
        |> Map.put(:y, y)

      _ ->
        desired =
          Enum.reduce(keys, desired, fn key, acc ->
            cond do
              key in [:x, "x"] -> Map.put(acc, key, x)
              key in [:y, "y"] -> Map.put(acc, key, y)
              true -> acc
            end
          end)

        desired
        |> Map.put_new(:x, x)
        |> Map.put_new(:y, y)
    end
  end

  def put_xy(desired, _x, _y), do: desired

  defp maybe_clamp_kelvin(desired, light) do
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

  defp maybe_filter_xy(desired, light) do
    x = x_value(desired)
    y = y_value(desired)

    cond do
      is_nil(x) or is_nil(y) ->
        desired

      supports_color?(light) ->
        put_xy(desired, x, y)

      true ->
        drop_xy(desired)
    end
  end

  defp normalize_xy_value(nil), do: nil
  defp normalize_xy_value(value), do: Float.round(Util.clamp(value, 0.0, 1.0), 4)
end
