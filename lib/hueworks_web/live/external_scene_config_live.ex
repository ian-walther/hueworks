defmodule HueworksWeb.ExternalSceneConfigLive do
  use Phoenix.LiveView

  alias Hueworks.ExternalScenes
  alias Hueworks.Repo
  alias Hueworks.Schemas.Bridge
  alias Hueworks.Util

  def mount(_params, _session, socket) do
    {:ok,
     assign(socket,
       bridge: nil,
       external_scenes: [],
       scene_options: [],
       save_status: nil,
       save_error: nil
     )}
  end

  def handle_params(%{"id" => id}, _uri, socket) do
    bridge_id = Util.parse_id(id)

    case Repo.get(Bridge, bridge_id) do
      %Bridge{type: :ha} = bridge ->
        {:noreply, load_page(socket, bridge)}

      _ ->
        {:noreply, push_navigate(socket, to: "/config")}
    end
  end

  def handle_event("sync_external_scenes", _params, socket) do
    case ExternalScenes.sync_home_assistant_scenes(socket.assigns.bridge) do
      {:ok, external_scenes} ->
        {:noreply,
         assign(socket,
           external_scenes: external_scenes,
           save_status: "Home Assistant scenes synced.",
           save_error: nil
         )}

      {:error, reason} ->
        {:noreply, assign(socket, save_status: nil, save_error: inspect(reason))}
    end
  end

  def handle_event("save_mapping", %{"external_scene_id" => id} = params, socket) do
    external_scene_id = Util.parse_id(id)

    case ExternalScenes.get_external_scene(external_scene_id) do
      nil ->
        {:noreply, assign(socket, save_status: nil, save_error: "External scene not found.")}

      external_scene ->
        case ExternalScenes.update_mapping(external_scene, params) do
          {:ok, _mapping} ->
            {:noreply,
             socket
             |> assign(
               external_scenes: ExternalScenes.list_external_scenes_for_bridge(socket.assigns.bridge.id),
               save_status: "Mapping saved.",
               save_error: nil
             )}

          {:error, changeset} ->
            message =
              changeset.errors
              |> Enum.map(fn {field, {text, _opts}} -> "#{field} #{text}" end)
              |> Enum.join(", ")

            {:noreply, assign(socket, save_status: nil, save_error: message)}
        end
    end
  end

  defp load_page(socket, bridge) do
    assign(socket,
      bridge: bridge,
      external_scenes: ExternalScenes.list_external_scenes_for_bridge(bridge.id),
      scene_options: ExternalScenes.list_mappable_scenes(),
      save_status: nil,
      save_error: nil
    )
  end
end
