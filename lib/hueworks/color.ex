defmodule Hueworks.Color do
  @moduledoc false

  alias Hueworks.Util

  def hs_to_xy(hue, saturation) do
    with hue when is_number(hue) <- Util.to_number(hue),
         saturation when is_number(saturation) <- Util.to_number(saturation) do
      hue = Util.normalize_hue_degrees(hue)
      saturation = Util.normalize_saturation(saturation) / 100.0
      {r, g, b} = hsv_to_rgb(hue, saturation, 1.0)
      {x, y} = rgb_to_xy(r, g, b)
      {round_float(x), round_float(y)}
    else
      _ -> nil
    end
  end

  defp hsv_to_rgb(hue, saturation, value) do
    chroma = value * saturation
    hue_prime = rem(Float.floor(hue / 60) |> trunc(), 6)
    segment = hue / 60
    x = chroma * (1 - abs(rem2(segment, 2) - 1))

    {r1, g1, b1} =
      case hue_prime do
        0 -> {chroma, x, 0.0}
        1 -> {x, chroma, 0.0}
        2 -> {0.0, chroma, x}
        3 -> {0.0, x, chroma}
        4 -> {x, 0.0, chroma}
        _ -> {chroma, 0.0, x}
      end

    m = value - chroma
    {r1 + m, g1 + m, b1 + m}
  end

  defp rgb_to_xy(r, g, b) do
    r = gamma_expand(r)
    g = gamma_expand(g)
    b = gamma_expand(b)

    x_val = r * 0.664_511 + g * 0.154_324 + b * 0.162_028
    y_val = r * 0.283_881 + g * 0.668_433 + b * 0.047_685
    z_val = r * 0.000_088 + g * 0.072_31 + b * 0.986_039

    sum = x_val + y_val + z_val

    if sum <= 0 do
      {0.0, 0.0}
    else
      {x_val / sum, y_val / sum}
    end
  end

  defp gamma_expand(value) when value > 0.04045,
    do: :math.pow((value + 0.055) / 1.055, 2.4)

  defp gamma_expand(value), do: value / 12.92

  defp rem2(value, divisor), do: value - divisor * :math.floor(value / divisor)

  defp round_float(value) when is_float(value), do: Float.round(value, 4)
  defp round_float(value), do: value
end
