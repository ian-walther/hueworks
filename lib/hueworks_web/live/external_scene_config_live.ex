defmodule HueworksWeb.ExternalSceneConfigLive do
  use Phoenix.LiveView

  import HueworksWeb.Notices

  alias Hueworks.ExternalScenes
  alias Hueworks.Repo
  alias Hueworks.Schemas.Bridge
  alias Hueworks.Util

  def mount(_params, _session, socket) do
    {:ok,
     assign(socket,
       bridge: nil,
       external_scenes: [],
       scene_options: []
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
         socket
         |> assign(external_scenes: external_scenes)
         |> put_notice(:info, "Home Assistant scenes synced.")}

      {:error, reason} ->
        {:noreply,
         socket
         |> put_notice(:error, inspect(reason))}
    end
  end

  def handle_event("save_mapping", %{"external_scene_id" => id} = params, socket) do
    external_scene_id = Util.parse_id(id)

    case ExternalScenes.get_external_scene(external_scene_id) do
      nil ->
        {:noreply,
         socket
         |> put_notice(:error, "External scene not found.")}

      external_scene ->
        case ExternalScenes.update_mapping(external_scene, params) do
          {:ok, _mapping} ->
            {:noreply,
             socket
             |> assign(
               external_scenes:
                 ExternalScenes.list_external_scenes_for_bridge(socket.assigns.bridge.id)
             )
             |> put_notice(:info, "Mapping saved.")}

          {:error, changeset} ->
            message =
              changeset.errors
              |> Enum.map(fn {field, {text, _opts}} -> "#{field} #{text}" end)
              |> Enum.join(", ")

            {:noreply,
             socket
             |> put_notice(:error, message)}
        end
    end
  end

  defp load_page(socket, bridge) do
    assign(socket,
      bridge: bridge,
      external_scenes: ExternalScenes.list_external_scenes_for_bridge(bridge.id),
      scene_options: ExternalScenes.list_mappable_scenes()
    )
  end
end
