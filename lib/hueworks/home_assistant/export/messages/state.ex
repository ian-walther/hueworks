defmodule Hueworks.HomeAssistant.Export.Messages.State do
  @moduledoc false

  alias Hueworks.ActiveScenes
  alias Hueworks.Control.State
  alias Hueworks.HomeAssistant.Export.Messages.RoomSceneOption
  alias Hueworks.Kelvin
  alias Hueworks.Schemas.Scene
  alias Hueworks.Util

  def light_state_payload(kind, entity) when kind in [:light, :group] and is_map(entity) do
    light_state_payload(entity, State.get(kind, entity.id) || %{})
  end

  def light_state_payload(entity, state) when is_map(entity) and is_map(state) do
    power = state_power_value(state)

    brightness =
      state
      |> fetch_state_value(:brightness)
      |> normalize_export_brightness()

    kelvin =
      state
      |> fetch_state_value(:kelvin)
      |> Kernel.||(fetch_state_value(state, :temperature))
      |> normalize_export_kelvin()

    x =
      state
      |> fetch_state_value(:x)
      |> normalize_xy_value()

    y =
      state
      |> fetch_state_value(:y)
      |> normalize_xy_value()

    %{"state" => power_to_mqtt_json(power)}
    |> maybe_put("brightness", brightness)
    |> maybe_put_color_state(entity, kelvin, x, y)
  end

  def switch_state_payload(kind, id) when kind in [:light, :group] and is_integer(id) do
    switch_state_payload(State.get(kind, id) || %{})
  end

  def switch_state_payload(state) when is_map(state) do
    case state_power_value(state) do
      :on -> "ON"
      :off -> "OFF"
      _ -> "None"
    end
  end

  def entity_export_mode(%{ha_export_mode: mode}) when mode in [:none, :switch, :light], do: mode
  def entity_export_mode(_entity), do: :none

  def normalize_power_payload(value) when value in [:on, :off], do: value
  def normalize_power_payload(value) when value in ["ON", "on"], do: :on
  def normalize_power_payload(value) when value in ["OFF", "off"], do: :off
  def normalize_power_payload(_value), do: nil

  def normalize_export_brightness(value) do
    case Util.to_number(value) do
      nil -> nil
      number -> Util.clamp(round(number), 0, 100)
    end
  end

  def normalize_export_kelvin(value) do
    case Util.to_number(value) do
      nil -> nil
      number -> round(number)
    end
  end

  def normalize_export_xy(%{} = color) do
    {normalize_xy_value(Map.get(color, "x")), normalize_xy_value(Map.get(color, "y"))}
  end

  def normalize_export_xy(_color), do: {nil, nil}

  def room_select_state_payload(room_id, scenes) when is_integer(room_id) and is_list(scenes) do
    active_scene_id =
      case ActiveScenes.get_for_room(room_id) do
        %{scene_id: scene_id} -> scene_id
        _ -> nil
      end

    scenes
    |> room_scene_options()
    |> Enum.find_value("Manual", fn %RoomSceneOption{label: label, scene: scene} ->
      if scene.id == active_scene_id, do: label, else: nil
    end)
  end

  def active_scene_name(room_id, scenes) when is_integer(room_id) and is_list(scenes) do
    case room_select_state_payload(room_id, scenes) do
      "Manual" -> nil
      value -> value
    end
  end

  def room_scene_options(scenes) when is_list(scenes) do
    duplicate_counts = Enum.frequencies_by(scenes, &scene_name/1)

    Enum.map(scenes, fn scene ->
      base_name = scene_name(scene)

      label =
        if duplicate_counts[base_name] > 1 do
          "#{base_name} (##{scene.id})"
        else
          base_name
        end

      %RoomSceneOption{label: label, scene: scene}
    end)
  end

  defp fetch_state_value(state, key) when is_map(state) and is_atom(key) do
    Map.get(state, key) || Map.get(state, Atom.to_string(key))
  end

  defp maybe_put_color_state(payload, entity, kelvin, x, y) do
    cond do
      entity.supports_color == true and is_number(x) and is_number(y) ->
        payload
        |> Map.put("color_mode", "xy")
        |> Map.put("color", %{"x" => x, "y" => y})

      entity.supports_temp == true and is_number(kelvin) ->
        payload
        |> Map.put("color_mode", "color_temp")
        |> Map.put("color_temp", round(kelvin))

      is_number(Map.get(payload, "brightness")) ->
        if supported_color_modes(entity) == ["brightness"] do
          Map.put(payload, "color_mode", "brightness")
        else
          payload
        end

      true ->
        payload
    end
  end

  def maybe_put_kelvin_range(payload, entity) do
    if entity.supports_temp == true do
      {min_kelvin, max_kelvin} = Kelvin.derive_range(entity)

      payload
      |> Map.put("color_temp_kelvin", true)
      |> Map.put("min_kelvin", min_kelvin)
      |> Map.put("max_kelvin", max_kelvin)
    else
      payload
    end
  end

  def supported_color_modes(entity) do
    cond do
      entity.supports_color == true and entity.supports_temp == true -> ["xy", "color_temp"]
      entity.supports_color == true -> ["xy"]
      entity.supports_temp == true -> ["color_temp"]
      true -> ["brightness"]
    end
  end

  defp normalize_xy_value(value) do
    case Util.to_number(value) do
      nil -> nil
      number -> Float.round(number, 4)
    end
  end

  defp power_to_mqtt_json(:on), do: "ON"
  defp power_to_mqtt_json(:off), do: "OFF"
  defp power_to_mqtt_json(_value), do: nil

  defp state_power_value(nil), do: nil

  defp state_power_value(state) when is_map(state) do
    case fetch_state_value(state, :power) do
      value when value in [:on, "on", "ON", true] -> :on
      value when value in [:off, "off", "OFF", false] -> :off
      _ -> nil
    end
  end

  defp scene_name(%Scene{} = scene), do: scene.display_name || scene.name

  defp maybe_put(payload, _key, nil), do: payload
  defp maybe_put(payload, key, value), do: Map.put(payload, key, value)
end
