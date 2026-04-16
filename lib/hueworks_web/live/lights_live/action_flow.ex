defmodule HueworksWeb.LightsLive.ActionFlow do
  @moduledoc false

  alias HueworksWeb.LightsLive.Actions
  alias HueworksWeb.LightsLive.StateUpdates

  @action_events [
    "toggle_on",
    "toggle_off",
    "toggle",
    "set_brightness",
    "set_color_temp",
    "set_color"
  ]

  def action_events, do: @action_events

  def run(event, params, assigns) when event in @action_events and is_map(params) and is_map(assigns) do
    case action_request(event, params, assigns) do
      {:ok, {:toggle, type, id, state_map}} ->
        case Actions.toggle(type, id, state_map) do
          {:ok, result} -> {:ok, StateUpdates.apply_action_result(assigns, result)}
          {:error, status} -> {:error, status}
        end

      {:ok, {type, id, action}} ->
        case Actions.dispatch(type, id, action) do
          {:ok, result} -> {:ok, StateUpdates.apply_action_result(assigns, result)}
          {:error, status} -> {:error, status}
        end

      {:error, status} ->
        {:error, status}
    end
  end

  defp action_request("toggle_on", %{"type" => type, "id" => id}, _assigns),
    do: {:ok, {type, id, :on}}

  defp action_request("toggle_off", %{"type" => type, "id" => id}, _assigns),
    do: {:ok, {type, id, :off}}

  defp action_request("toggle", %{"type" => "light", "id" => id}, assigns),
    do: {:ok, {:toggle, "light", id, assigns.light_state}}

  defp action_request("toggle", %{"type" => "group", "id" => id}, assigns),
    do: {:ok, {:toggle, "group", id, assigns.group_state}}

  defp action_request("toggle", %{"type" => type, "id" => id}, _assigns),
    do: {:error, "ERROR #{type} #{id}: unsupported"}

  defp action_request(
         "set_brightness",
         %{"type" => type, "id" => id, "level" => level},
         _assigns
       ),
       do: {:ok, {type, id, {:brightness, level}}}

  defp action_request(
         "set_color_temp",
         %{"type" => type, "id" => id, "kelvin" => kelvin},
         _assigns
       ),
       do: {:ok, {type, id, {:color_temp, kelvin}}}

  defp action_request(
         "set_color",
         %{"type" => type, "id" => id, "hue" => hue, "saturation" => saturation},
         _assigns
       ),
       do: {:ok, {type, id, {:color, hue, saturation}}}
end
