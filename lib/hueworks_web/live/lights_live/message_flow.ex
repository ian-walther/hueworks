defmodule HueworksWeb.LightsLive.MessageFlow do
  @moduledoc false

  alias Hueworks.Control.State
  alias HueworksWeb.LightsLive.Loader
  alias HueworksWeb.LightsLive.StateUpdates

  def refresh(assigns) when is_map(assigns) do
    State.bootstrap()

    assigns
    |> Loader.reload_assigns()
    |> Map.put(:status, "Reloaded database snapshot")
  end

  def info_updates({:active_scene_updated, room_id, scene_id}, assigns)
      when is_integer(room_id) and is_map(assigns) do
    {:ok, StateUpdates.put_active_scene(assigns, room_id, scene_id)}
  end

  def info_updates({:control_state, :light, id, state}, assigns)
      when is_integer(id) and is_map(state) and is_map(assigns) do
    {:ok, StateUpdates.replace_control_state(assigns, :light, id, state)}
  end

  def info_updates({:control_state, :group, id, state}, assigns)
      when is_integer(id) and is_map(state) and is_map(assigns) do
    {:ok, StateUpdates.replace_control_state(assigns, :group, id, state)}
  end

  def info_updates(_message, _assigns), do: :ignore
end
