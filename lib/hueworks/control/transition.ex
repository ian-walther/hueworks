defmodule Hueworks.Control.Transition do
  @moduledoc false

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
    case Map.get(opts, :transition_ms) || Map.get(opts, "transition_ms") do
      value when is_integer(value) and value > 0 -> value
      _ -> nil
    end
  end

  def transition_ms(_opts), do: nil

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
end
