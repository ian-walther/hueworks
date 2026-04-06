defmodule Hueworks.Color do
  @moduledoc false

  alias Hueworks.Util

  def hsb_to_rgb(hue, saturation, brightness) do
    with hue when is_number(hue) <- Util.to_number(hue),
         saturation when is_number(saturation) <- Util.to_number(saturation),
         brightness when is_number(brightness) <- Util.to_number(brightness) do
      hue = Util.normalize_hue_degrees(hue)
      saturation = Util.normalize_saturation(saturation) / 100.0
      brightness = Util.normalize_percent(brightness) / 100.0

      {r, g, b} = hsv_to_rgb(hue, saturation, brightness)
      {rgb_channel(r), rgb_channel(g), rgb_channel(b)}
    else
      _ -> nil
    end
  end

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

  def kelvin_to_xy(kelvin) do
    with kelvin when is_number(kelvin) <- Util.to_number(kelvin) do
      {r, g, b} =
        kelvin
        |> normalize_kelvin()
        |> kelvin_to_rgb()

      r = r / 255.0
      g = g / 255.0
      b = b / 255.0

      rgb_to_xy(r, g, b)
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

  defp kelvin_to_rgb(kelvin) do
    temperature = kelvin / 100.0

    red =
      cond do
        temperature <= 66 ->
          255

        true ->
          329.698_727_446 * :math.pow(temperature - 60, -0.133_204_759_2)
      end

    green =
      cond do
        temperature <= 66 ->
          99.470_802_586_1 * :math.log(temperature) - 161.119_568_166_1

        true ->
          288.122_169_528_3 * :math.pow(temperature - 60, -0.075_514_849_2)
      end

    blue =
      cond do
        temperature >= 66 ->
          255

        temperature <= 19 ->
          0

        true ->
          138.517_731_223_1 * :math.log(temperature - 10) - 305.044_792_730_7
      end

    {
      rgb_channel(red / 255.0),
      rgb_channel(green / 255.0),
      rgb_channel(blue / 255.0)
    }
  end

  defp normalize_kelvin(kelvin) do
    kelvin
    |> round()
    |> min(40_000)
    |> max(1_000)
  end

  defp rgb_channel(value) do
    value
    |> Kernel.*(255)
    |> round()
    |> min(255)
    |> max(0)
  end
end
