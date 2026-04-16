defmodule HueworksWeb.LightsLive.Presentation do
  @moduledoc false

  alias Hueworks.Color

  def state_value(state_map, id, key, fallback) do
    state_map
    |> Map.get(id, %{})
    |> Map.get(key, fallback)
  end

  def manual_adjustment_locked?(active_scene_by_room, room_id)
      when is_map(active_scene_by_room) do
    is_integer(room_id) and Map.has_key?(active_scene_by_room, room_id)
  end

  def manual_adjustment_locked?(_active_scene_by_room, _room_id), do: false

  def color_preview(state_map, id) do
    state = Map.get(state_map, id, %{})

    {hue, saturation} =
      case Color.xy_to_hs(Map.get(state, :x), Map.get(state, :y)) do
        {hue, saturation} -> {hue, saturation}
        nil -> {0, 100}
      end

    brightness =
      case state_value(state_map, id, :brightness, 100) do
        value when is_integer(value) -> value
        value when is_float(value) -> round(value)
        _ -> 100
      end

    %{hue: hue, saturation: saturation, brightness: brightness}
  end

  def color_preview_style(state_map, id) do
    %{hue: hue, saturation: saturation, brightness: brightness} = color_preview(state_map, id)
    {r, g, b} = Color.hsb_to_rgb(hue, saturation, brightness) || {143, 177, 255}
    "background-color: rgb(#{r} #{g} #{b});"
  end

  def color_preview_label(state_map, id) do
    %{hue: hue, saturation: saturation, brightness: brightness} = color_preview(state_map, id)
    "Color: #{hue}°, #{saturation}% saturation, #{brightness}% brightness"
  end

  def color_saturation_scale_style(state_map, id) do
    %{hue: hue, brightness: brightness} = color_preview(state_map, id)
    {r1, g1, b1} = Color.hsb_to_rgb(hue, 0, brightness) || {255, 255, 255}
    {r2, g2, b2} = Color.hsb_to_rgb(hue, 100, brightness) || {255, 255, 255}
    "background: linear-gradient(90deg, rgb(#{r1} #{g1} #{b1}), rgb(#{r2} #{g2} #{b2}));"
  end
end
