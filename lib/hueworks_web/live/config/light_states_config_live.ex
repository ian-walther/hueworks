defmodule HueworksWeb.LightStatesConfigLive do
  use Phoenix.LiveView

  import HueworksWeb.Notices

  alias Hueworks.Scenes
  alias Hueworks.Schemas.LightState

  def mount(_params, _session, socket) do
    {:ok, assign(socket, light_states: list_light_states())}
  end

  def handle_event("duplicate_light_state", %{"id" => id}, socket) do
    case Scenes.duplicate_light_state(Hueworks.Util.parse_id(id)) do
      {:ok, state} ->
        {:noreply,
         socket
         |> assign(light_states: list_light_states())
         |> put_notice(:info, "Duplicated #{state.name}.")
         |> push_navigate(to: "/config/light-states/#{state.id}/edit")}

      {:error, _reason} ->
        {:noreply, put_notice(socket, :error, "Unable to duplicate light state.")}
    end
  end

  def handle_event("delete_light_state", %{"id" => id}, socket) do
    light_state_id = Hueworks.Util.parse_id(id)

    case Scenes.delete_light_state(light_state_id) do
      {:ok, _state} ->
        {:noreply,
         socket
         |> assign(light_states: list_light_states())
         |> put_notice(:info, "Light state deleted.")}

      {:error, :in_use} ->
        usages =
          Scenes.light_state_usages(light_state_id)
          |> Enum.map_join(", ", fn usage -> "#{usage.room_name} / #{usage.scene_name}" end)

        {:noreply, put_notice(socket, :error, "Light state is in use by: #{usages}")}

      {:error, _reason} ->
        {:noreply, put_notice(socket, :error, "Unable to delete light state.")}
    end
  end

  defp list_light_states, do: Scenes.list_editable_light_states_with_usage()

  def state_label(%LightState{} = state), do: HueworksWeb.ConfigHelpers.state_label(state)
end
