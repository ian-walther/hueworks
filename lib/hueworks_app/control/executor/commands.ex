defmodule Hueworks.Control.Executor.Commands do
  @moduledoc false

  def commands_for_action(%{desired: desired}) when is_map(desired) do
    desired
    |> commands_for_desired()
  end

  defp commands_for_desired(desired) do
    power = Map.get(desired, :power) || Map.get(desired, "power")

    case power do
      :off -> [:off]
      "off" -> [:off]
      _ -> build_on_commands(desired, power)
    end
  end

  defp build_on_commands(desired, power) do
    commands = if power in [:on, "on"], do: [:on], else: []
    brightness = value_or_nil(desired, [:brightness, "brightness"])
    kelvin = value_or_nil(desired, [:kelvin, "kelvin", :temperature, "temperature"])
    x = value_or_nil(desired, [:x, "x"])
    y = value_or_nil(desired, [:y, "y"])

    commands
    |> maybe_add(:brightness, brightness)
    |> maybe_add_color(kelvin, x, y)
  end

  defp maybe_add(commands, _key, nil), do: commands
  defp maybe_add(commands, key, value), do: commands ++ [{key, normalize_value(value)}]

  defp maybe_add_color(commands, _kelvin, x, y) when not is_nil(x) and not is_nil(y) do
    commands ++ [{:xy, {normalize_value(x), normalize_value(y)}}]
  end

  defp maybe_add_color(commands, kelvin, _x, _y), do: maybe_add(commands, :color_temp, kelvin)

  defp value_or_nil(desired, keys) do
    Enum.reduce_while(keys, nil, fn key, _acc ->
      if Map.has_key?(desired, key) do
        {:halt, Map.get(desired, key)}
      else
        {:cont, nil}
      end
    end)
  end

  defp normalize_value(value) when is_binary(value) do
    case Float.parse(value) do
      {number, ""} when floor(number) == number -> trunc(number)
      {number, ""} -> number
      _ -> value
    end
  end

  defp normalize_value(value), do: value
end
