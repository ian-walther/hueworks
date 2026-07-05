defmodule Hueworks.Control.GroupState do
  @moduledoc false

  alias Hueworks.Control.State

  def derive_from_light_ids(light_ids) when is_list(light_ids) do
    light_ids
    |> Enum.map(&State.get(:light, &1))
    |> Enum.reject(&is_nil/1)
    |> derive_from_states(length(light_ids))
  end

  def derive_from_light_ids(_light_ids), do: %{}

  def derive_from_states(states, expected_count)
      when is_list(states) and is_integer(expected_count) do
    on_states = Enum.filter(states, &(normalize_power(fetch_value(&1, :power)) == :on))
    off_states = Enum.filter(states, &(normalize_power(fetch_value(&1, :power)) == :off))

    base =
      cond do
        on_states != [] -> %{power: :on}
        expected_count > 0 and length(off_states) == expected_count -> %{power: :off}
        true -> %{}
      end

    base
    |> maybe_put_group_brightness(on_states)
    |> maybe_put_group_kelvin(on_states)
    |> maybe_put_group_xy(on_states)
  end

  def derive_from_states(_states, _expected_count), do: %{}

  def member_attrs_from_group(%{power: :on} = attrs, desired_state, current_state) do
    cond do
      explicit_power?(desired_state, :on) ->
        attrs

      explicit_power?(desired_state, :off) ->
        Map.put(attrs, :power, :off)

      explicit_power?(current_state, :off) ->
        Map.delete(attrs, :power)

      true ->
        attrs
    end
  end

  def member_attrs_from_group(attrs, _desired_state, _current_state), do: attrs

  defp maybe_put_group_brightness(group_state, on_states) do
    on_states
    |> numeric_values(:brightness)
    |> put_average_if_complete(group_state, :brightness, length(on_states))
  end

  defp maybe_put_group_kelvin(group_state, on_states) do
    kelvin_values = numeric_values(on_states, :kelvin)

    if kelvin_values != [] and length(kelvin_values) == length(on_states) do
      min_k = Enum.min(kelvin_values)
      max_k = Enum.max(kelvin_values)

      if max_k - min_k <= 50 do
        Map.put(group_state, :kelvin, round(Enum.sum(kelvin_values) / length(kelvin_values)))
      else
        group_state
      end
    else
      group_state
    end
  end

  defp maybe_put_group_xy(%{kelvin: _kelvin} = group_state, _on_states), do: group_state

  defp maybe_put_group_xy(group_state, on_states) do
    x_values = numeric_values(on_states, :x)
    y_values = numeric_values(on_states, :y)

    if xy_values_complete?(x_values, y_values, on_states) and values_within?(x_values, 0.01) and
         values_within?(y_values, 0.01) do
      group_state
      |> Map.put(:x, Float.round(Enum.sum(x_values) / length(x_values), 4))
      |> Map.put(:y, Float.round(Enum.sum(y_values) / length(y_values), 4))
    else
      group_state
    end
  end

  defp numeric_values(states, key) do
    states
    |> Enum.map(&fetch_number(&1, key))
    |> Enum.reject(&is_nil/1)
  end

  defp fetch_number(state, key) do
    case fetch_value(state, key) do
      value when is_number(value) -> value
      _ -> nil
    end
  end

  defp fetch_value(state, key) when is_map(state) and is_atom(key) do
    Map.get(state, key)
  end

  defp fetch_value(_state, _key), do: nil

  defp put_average_if_complete([], group_state, _key, _expected_count), do: group_state

  defp put_average_if_complete(values, group_state, key, expected_count) do
    if length(values) == expected_count do
      Map.put(group_state, key, round(Enum.sum(values) / length(values)))
    else
      group_state
    end
  end

  defp xy_values_complete?(x_values, y_values, on_states) do
    expected_count = length(on_states)

    expected_count > 0 and length(x_values) == expected_count and
      length(y_values) == expected_count
  end

  defp values_within?(values, tolerance) when is_list(values) and values != [] do
    Enum.max(values) - Enum.min(values) <= tolerance
  end

  defp values_within?(_values, _tolerance), do: false

  defp explicit_power?(state, expected_power) when expected_power in [:on, :off] do
    case state do
      %{power: power} -> normalize_power(power) == expected_power
      _ -> false
    end
  end

  defp normalize_power(:on), do: :on
  defp normalize_power(:off), do: :off
  defp normalize_power(_power), do: nil
end
