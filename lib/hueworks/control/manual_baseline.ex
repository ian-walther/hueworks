defmodule Hueworks.Control.ManualBaseline do
  @moduledoc false

  alias Hueworks.Util

  @default_on_state %{brightness: 100, kelvin: 3000}

  def on_state do
    Application.get_env(:hueworks, :manual_on_baseline, @default_on_state)
    |> normalize_state()
  end

  def power_on_state do
    on_state()
    |> Map.put(:power, :on)
  end

  defp normalize_state(state) when is_map(state) do
    %{}
    |> maybe_put_integer(:brightness, Map.get(state, :brightness))
    |> maybe_put_integer(:kelvin, Map.get(state, :kelvin))
  end

  defp normalize_state(_state), do: @default_on_state

  defp maybe_put_integer(attrs, _key, nil), do: attrs

  defp maybe_put_integer(attrs, key, value) do
    case Util.to_number(value) do
      nil -> attrs
      parsed -> Map.put(attrs, key, round(parsed))
    end
  end
end
