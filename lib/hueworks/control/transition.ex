defmodule Hueworks.Control.Transition do
  @moduledoc false

  alias Hueworks.Util

  def apply_opts(transition_ms) when is_integer(transition_ms) and transition_ms > 0 do
    %{transition_ms: transition_ms}
  end

  def apply_opts(_transition_ms), do: %{}

  def transition_ms(opts) when is_list(opts) do
    case Keyword.get(opts, :transition_ms) do
      value when is_integer(value) and value > 0 -> value
      _ -> nil
    end
  end

  def transition_ms(opts) when is_map(opts) do
    case Map.get(opts, :transition_ms) do
      value when is_integer(value) and value > 0 -> value
      _ -> nil
    end
  end

  def transition_ms(_opts), do: nil

  def brightness_scalable?(desired) when is_map(desired) do
    has_brightness_key?(desired) or off_target?(desired)
  end

  def brightness_scalable?(_desired), do: false

  def brightness_delta_percent(desired, physical)
      when is_map(desired) and is_map(physical) do
    with target when is_integer(target) <- target_brightness_percent(desired),
         current when is_integer(current) <- current_brightness_percent(physical) do
      abs(target - current)
    else
      _ -> nil
    end
  end

  def brightness_delta_percent(_desired, _physical), do: nil

  def hue_transitiontime(opts) do
    case transition_ms(opts) do
      value when is_integer(value) -> round(value / 100)
      _ -> nil
    end
  end

  def seconds(opts) do
    case transition_ms(opts) do
      value when is_integer(value) -> Float.round(value / 1000, 3)
      _ -> nil
    end
  end

  defp target_brightness_percent(desired) do
    cond do
      has_brightness_key?(desired) ->
        desired
        |> brightness_value()
        |> Util.normalize_percent()
        |> round()

      off_target?(desired) ->
        0

      true ->
        nil
    end
  end

  defp current_brightness_percent(physical) do
    cond do
      has_brightness_key?(physical) ->
        physical
        |> brightness_value()
        |> Util.normalize_percent()
        |> round()

      off_target?(physical) ->
        0

      true ->
        nil
    end
  end

  defp brightness_value(state) do
    Map.get(state, :brightness)
  end

  defp has_brightness_key?(state) do
    Map.has_key?(state, :brightness)
  end

  defp off_target?(state) do
    Map.get(state, :power) == :off
  end
end
