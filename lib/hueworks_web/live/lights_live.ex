defmodule HueworksWeb.LightsLive do
  use Phoenix.LiveView

  alias HueworksWeb.LightsLive.ActionFlow
  alias HueworksWeb.LightsLive.EditFlow
  alias HueworksWeb.LightsLive.Editor
  alias HueworksWeb.LightsLive.FilterState
  alias HueworksWeb.LightsLive.Filters
  alias HueworksWeb.LightsLive.Loader
  alias HueworksWeb.LightsLive.MessageFlow
  alias HueworksWeb.LightsLive.Presentation

  @action_events ~w(toggle_on toggle_off toggle set_brightness set_color_temp set_color)

  @impl true
  def mount(params, session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(Hueworks.PubSub, "control_state")
      Phoenix.PubSub.subscribe(Hueworks.PubSub, Hueworks.ActiveScenes.topic())
    end

    filter_session_id = session["filter_session_id"]

    {:ok,
     assign(
       socket,
       Loader.mount_assigns(params, filter_session_id)
       |> Map.merge(Editor.default_assigns())
     )}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    updates = FilterState.param_updates(params)

    if map_size(updates) > 0 do
      {:noreply, assign(socket, FilterState.store(socket.assigns, updates))}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("refresh", _params, socket) do
    {:noreply, assign(socket, MessageFlow.refresh(socket.assigns))}
  end

  def handle_event(event, params, socket)
      when event in [
             "set_group_filter",
             "set_group_room_filter",
             "set_light_filter",
             "set_light_room_filter",
             "toggle_group_disabled",
             "toggle_light_disabled",
             "toggle_light_linked"
           ] do
    {:noreply,
     socket
     |> assign(
       FilterState.store(
         socket.assigns,
         FilterState.event_updates(event, params, socket.assigns.rooms)
       )
     )}
  end

  def handle_event(event, params, socket)
      when event in [
             "open_edit",
             "close_edit",
             "show_link_selector",
             "update_display_name",
             "save_display_name",
             "update_edit_fields",
             "save_edit_fields"
           ] do
    case EditFlow.run(event, params, socket.assigns, &Loader.reload_assigns/1) do
      {:ok, updates} -> {:noreply, assign(socket, updates)}
      {:error, status} -> {:noreply, assign(socket, status: status)}
    end
  end

  def handle_event(event, params, socket) when event in @action_events do
    case ActionFlow.run(event, params, socket.assigns) do
      {:ok, updates} -> {:noreply, assign(socket, updates)}
      {:error, status} -> {:noreply, assign(socket, status: status)}
    end
  end

  @impl true
  def handle_info(message, socket) do
    case MessageFlow.info_updates(message, socket.assigns) do
      {:ok, updates} -> {:noreply, assign(socket, updates)}
      :ignore -> {:noreply, socket}
    end
  end
end
