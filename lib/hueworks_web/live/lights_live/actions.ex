defmodule HueworksWeb.LightsLive.Actions do
  @moduledoc false

  alias Hueworks.Color
  alias Hueworks.Groups
  alias Hueworks.Lights.ManualControl
  alias Hueworks.Util
  alias HueworksWeb.LightsLive.Entities

  defmodule Result do
    @moduledoc false

    @enforce_keys [:target_type, :target_id, :attrs, :status]
    defstruct [:target_type, :target_id, :attrs, :status]
  end

  def dispatch("light", id, {:brightness, level}) do
    with {:ok, light} <- Entities.fetch_light(id),
         {:ok, parsed} <- Util.parse_level(level),
         {:ok, _diff} <- ManualControl.apply_updates(light.room_id, [light.id], %{brightness: parsed}) do
      {:ok,
       %Result{
         target_type: :light,
         target_id: light.id,
         attrs: %{brightness: parsed},
         status: "BRIGHTNESS light #{Util.display_name(light)} -> #{parsed}%"
       }}
    else
      {:error, :scene_active_manual_adjustment_not_allowed} ->
        {:error, scene_active_manual_adjustment_message()}

      {:error, reason} ->
        {:error, "ERROR light #{id}: #{Util.format_reason(reason)}"}
    end
  end

  def dispatch("group", id, {:brightness, level}) do
    with {:ok, group} <- Entities.fetch_group(id),
         {:ok, parsed} <- Util.parse_level(level),
         light_ids when light_ids != [] <- group_light_ids(group.id),
         {:ok, _diff} <- ManualControl.apply_updates(group.room_id, light_ids, %{brightness: parsed}) do
      {:ok,
       %Result{
         target_type: :group,
         target_id: group.id,
         attrs: %{brightness: parsed},
         status: "BRIGHTNESS group #{Util.display_name(group)} -> #{parsed}%"
       }}
    else
      [] ->
        {:error, "ERROR group #{id}: no_members"}

      {:error, :scene_active_manual_adjustment_not_allowed} ->
        {:error, scene_active_manual_adjustment_message()}

      {:error, reason} ->
        {:error, "ERROR group #{id}: #{Util.format_reason(reason)}"}
    end
  end

  def dispatch("light", id, {:color_temp, kelvin}) do
    with {:ok, light} <- Entities.fetch_light(id),
         {:ok, parsed} <- Util.parse_kelvin(kelvin),
         {:ok, _diff} <- ManualControl.apply_updates(light.room_id, [light.id], %{kelvin: parsed}) do
      {:ok,
       %Result{
         target_type: :light,
         target_id: light.id,
         attrs: %{kelvin: parsed},
         status: "TEMP light #{Util.display_name(light)} -> #{parsed}K"
       }}
    else
      {:error, :scene_active_manual_adjustment_not_allowed} ->
        {:error, scene_active_manual_adjustment_message()}

      {:error, reason} ->
        {:error, "ERROR light #{id}: #{Util.format_reason(reason)}"}
    end
  end

  def dispatch("group", id, {:color_temp, kelvin}) do
    with {:ok, group} <- Entities.fetch_group(id),
         {:ok, parsed} <- Util.parse_kelvin(kelvin),
         light_ids when light_ids != [] <- group_light_ids(group.id),
         {:ok, _diff} <- ManualControl.apply_updates(group.room_id, light_ids, %{kelvin: parsed}) do
      {:ok,
       %Result{
         target_type: :group,
         target_id: group.id,
         attrs: %{kelvin: parsed},
         status: "TEMP group #{Util.display_name(group)} -> #{parsed}K"
       }}
    else
      [] ->
        {:error, "ERROR group #{id}: no_members"}

      {:error, :scene_active_manual_adjustment_not_allowed} ->
        {:error, scene_active_manual_adjustment_message()}

      {:error, reason} ->
        {:error, "ERROR group #{id}: #{Util.format_reason(reason)}"}
    end
  end

  def dispatch("light", id, {:color, hue, saturation}) do
    with {:ok, light} <- Entities.fetch_light(id),
         {:ok, parsed_hue, parsed_saturation, x, y} <- parse_color(hue, saturation),
         {:ok, _diff} <- ManualControl.apply_updates(light.room_id, [light.id], %{power: :on, x: x, y: y}) do
      {:ok,
       %Result{
         target_type: :light,
         target_id: light.id,
         attrs: %{power: :on, x: x, y: y, kelvin: nil, temperature: nil},
         status: "COLOR light #{Util.display_name(light)} -> #{parsed_hue}° / #{parsed_saturation}%"
       }}
    else
      {:error, :scene_active_manual_adjustment_not_allowed} ->
        {:error, scene_active_manual_adjustment_message()}

      {:error, reason} ->
        {:error, "ERROR light #{id}: #{Util.format_reason(reason)}"}
    end
  end

  def dispatch("group", id, {:color, hue, saturation}) do
    with {:ok, group} <- Entities.fetch_group(id),
         {:ok, parsed_hue, parsed_saturation, x, y} <- parse_color(hue, saturation),
         light_ids when light_ids != [] <- group_light_ids(group.id),
         {:ok, _diff} <- ManualControl.apply_updates(group.room_id, light_ids, %{power: :on, x: x, y: y}) do
      {:ok,
       %Result{
         target_type: :group,
         target_id: group.id,
         attrs: %{power: :on, x: x, y: y, kelvin: nil, temperature: nil},
         status: "COLOR group #{Util.display_name(group)} -> #{parsed_hue}° / #{parsed_saturation}%"
       }}
    else
      [] ->
        {:error, "ERROR group #{id}: no_members"}

      {:error, :scene_active_manual_adjustment_not_allowed} ->
        {:error, scene_active_manual_adjustment_message()}

      {:error, reason} ->
        {:error, "ERROR group #{id}: #{Util.format_reason(reason)}"}
    end
  end

  def dispatch("light", id, action) when action in [:on, :off] do
    with {:ok, light} <- Entities.fetch_light(id),
         {:ok, updated_attrs} <- ManualControl.apply_power_action(light.room_id, [light.id], action) do
      {:ok,
       %Result{
         target_type: :light,
         target_id: light.id,
         attrs: updated_attrs,
         status: "#{action_label(action)} light #{Util.display_name(light)}"
       }}
    else
      {:error, reason} ->
        {:error, "ERROR light #{id}: #{Util.format_reason(reason)}"}
    end
  end

  def dispatch("group", id, action) when action in [:on, :off] do
    with {:ok, group} <- Entities.fetch_group(id),
         light_ids when light_ids != [] <- group_light_ids(group.id),
         {:ok, updated_attrs} <- ManualControl.apply_power_action(group.room_id, light_ids, action) do
      {:ok,
       %Result{
         target_type: :group,
         target_id: group.id,
         attrs: updated_attrs,
         status: "#{action_label(action)} group #{Util.display_name(group)}"
       }}
    else
      [] ->
        {:error, "ERROR group #{id}: no_members"}

      {:error, reason} ->
        {:error, "ERROR group #{id}: #{Util.format_reason(reason)}"}
    end
  end

  def dispatch(type, id, _action), do: {:error, "ERROR #{type} #{id}: unsupported"}

  def toggle("light", id, light_state) do
    with {:ok, light} <- Entities.fetch_light(id) do
      dispatch("light", id, toggle_action(light_state, light.id))
    else
      {:error, reason} ->
        {:error, "ERROR light #{id}: #{Util.format_reason(reason)}"}
    end
  end

  def toggle("group", id, group_state) do
    with {:ok, group} <- Entities.fetch_group(id) do
      dispatch("group", id, toggle_action(group_state, group.id))
    else
      {:error, reason} ->
        {:error, "ERROR group #{id}: #{Util.format_reason(reason)}"}
    end
  end

  def toggle(type, id, _state_map), do: {:error, "ERROR #{type} #{id}: unsupported"}

  defp group_light_ids(group_id) when is_integer(group_id), do: Groups.member_light_ids(group_id)

  defp toggle_action(state_map, id) do
    case Map.get(state_map, id, %{}) do
      %{power: power} when power in [:on, "on", true] -> :off
      _ -> :on
    end
  end

  defp action_label(:on), do: "ON"
  defp action_label(:off), do: "OFF"

  defp scene_active_manual_adjustment_message do
    "Brightness, temperature, and color are read-only while a scene is active. Deactivate the scene to adjust them manually."
  end

  defp parse_color(hue, saturation) do
    with parsed_hue when is_integer(parsed_hue) <- Util.normalize_hue_degrees(hue),
         parsed_saturation when is_integer(parsed_saturation) <-
           Util.normalize_saturation(saturation),
         {x, y} when is_number(x) and is_number(y) <- Color.hs_to_xy(parsed_hue, parsed_saturation) do
      {:ok, parsed_hue, parsed_saturation, x, y}
    else
      _ -> {:error, :invalid_color}
    end
  end
end
