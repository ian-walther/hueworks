defmodule HueworksWeb.ControlLive do
  use Phoenix.LiveView

  import Ecto.Query, only: [from: 2]

  alias Hueworks.ActiveScenes
  alias Hueworks.Control.State
  alias Hueworks.Groups
  alias Hueworks.Groups.Topology
  alias Hueworks.Lights
  alias Hueworks.Lights.ManualControl
  alias Hueworks.Repo
  alias Hueworks.Rooms
  alias Hueworks.Scenes
  alias Hueworks.Schemas.GroupLight
  alias Hueworks.Util
  alias HueworksWeb.LightsLive.Actions
  alias HueworksWeb.LightsLive.DisplayState
  alias HueworksWeb.LightsLive.Presentation
  alias HueworksWeb.LightsLive.StateUpdates

  @manual_adjustment_events ~w(set_brightness set_color_temp set_color)

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(Hueworks.PubSub, "control_state")
      Phoenix.PubSub.subscribe(Hueworks.PubSub, ActiveScenes.topic())
    end

    {:ok,
     socket
     |> assign(expanded_group_keys: MapSet.new(), selected_control_target: nil, status: nil)
     |> assign(control_assigns())}
  end

  @impl true
  def handle_event("refresh", _params, socket) do
    State.bootstrap()

    {:noreply,
     socket
     |> assign(control_assigns())
     |> put_notice(:info, "Reloaded control snapshot")}
  end

  def handle_event("toggle_scene", %{"id" => id}, socket) do
    with scene_id when is_integer(scene_id) <- Util.parse_id(id),
         %{} = scene <- Scenes.get_scene(scene_id) do
      case ActiveScenes.get_for_room(scene.room_id) do
        %{scene_id: ^scene_id} ->
          _ = ActiveScenes.clear_for_room(scene.room_id)

        current_active ->
          _ =
            Scenes.activate_scene(scene_id,
              trace: scene_activation_trace(scene.room_id, current_active, scene_id)
            )
      end

      {:noreply,
       socket
       |> assign(active_scene_by_room: active_scene_by_room())
       |> close_selected_light_if_locked()}
    else
      _ -> {:noreply, socket}
    end
  end

  def handle_event("toggle_room_power", %{"room_id" => room_id, "action" => action}, socket) do
    with room_id when is_integer(room_id) <- Util.parse_id(room_id),
         action when action in [:on, :off] <- parse_power_action(action),
         %{} = room_model <- room_model(socket.assigns.room_models, room_id),
         light_ids when light_ids != [] <- Enum.map(room_model.lights, & &1.id),
         {:ok, attrs} <- ManualControl.apply_power_action(room_id, light_ids, action) do
      {:noreply,
       socket
       |> assign(update_room_control_state(socket.assigns, room_model, attrs))
       |> put_notice(
         :info,
         "#{String.upcase(to_string(action))} #{Util.display_name(room_model.room)}"
       )}
    else
      [] ->
        {:noreply, put_notice(socket, :error, "No lights in room")}

      {:error, reason} ->
        {:noreply, put_notice(socket, :error, "ERROR room: #{Util.format_reason(reason)}")}

      _ ->
        {:noreply, socket}
    end
  end

  def handle_event("toggle", %{"type" => type, "id" => id}, socket)
      when type in ["light", "group"] do
    state_map =
      if type == "light", do: socket.assigns.light_state, else: socket.assigns.group_state

    case Actions.toggle(type, id, state_map) do
      {:ok, result} ->
        {:noreply,
         socket
         |> assign(StateUpdates.apply_action_result(socket.assigns, result))
         |> maybe_put_status_flash()}

      {:error, status} ->
        {:noreply, put_notice(socket, :error, status)}
    end
  end

  def handle_event("open_light_control", %{"id" => id}, socket) do
    with light_id when is_integer(light_id) <- Util.parse_id(id),
         %{} = light <- Enum.find(socket.assigns.lights, &(&1.id == light_id)),
         false <- manual_adjustment_locked?(socket.assigns, light) do
      {:noreply, assign(socket, selected_control_target: {:light, light.id})}
    else
      true ->
        {:noreply,
         put_notice(
           socket,
           :error,
           "Brightness, temperature, and color are unavailable while a scene is active."
         )}

      _ ->
        {:noreply, socket}
    end
  end

  def handle_event("open_group_control", %{"id" => id}, socket) do
    with group_id when is_integer(group_id) <- Util.parse_id(id),
         %{} = group <- Enum.find(socket.assigns.groups, &(&1.id == group_id)),
         false <- manual_adjustment_locked?(socket.assigns, group) do
      {:noreply, assign(socket, selected_control_target: {:group, group.id})}
    else
      true ->
        {:noreply,
         put_notice(
           socket,
           :error,
           "Brightness, temperature, and color are unavailable while a scene is active."
         )}

      _ ->
        {:noreply, socket}
    end
  end

  def handle_event("close_light_control", _params, socket) do
    {:noreply, assign(socket, selected_control_target: nil)}
  end

  def handle_event(event, %{"type" => type} = params, socket)
      when event in @manual_adjustment_events and type in ["light", "group"] do
    case manual_adjustment_request(event, params) do
      {:ok, {type, id, action}} ->
        with target_id when is_integer(target_id) <- Util.parse_id(id),
             target_type <- control_target_type(type),
             %{} = target <- control_target(socket.assigns, target_type, target_id),
             false <- manual_adjustment_locked?(socket.assigns, target),
             {:ok, result} <- Actions.dispatch(type, id, action) do
          {:noreply,
           socket
           |> assign(StateUpdates.apply_action_result(socket.assigns, result))
           |> maybe_put_status_flash()}
        else
          true ->
            {:noreply,
             put_notice(
               socket,
               :error,
               "Brightness, temperature, and color are unavailable while a scene is active."
             )}

          {:error, status} when is_binary(status) ->
            {:noreply, put_notice(socket, :error, status)}

          {:error, reason} ->
            {:noreply, put_notice(socket, :error, "ERROR #{type}: #{Util.format_reason(reason)}")}

          _ ->
            {:noreply, socket}
        end

      {:error, status} ->
        {:noreply, put_notice(socket, :error, status)}
    end
  end

  def handle_event(
        "toggle_group_expanded",
        %{"room_id" => room_id, "group_id" => group_id},
        socket
      ) do
    key = group_expanded_key(room_id, group_id)
    expanded_group_keys = Map.get(socket.assigns, :expanded_group_keys, MapSet.new())

    expanded_group_keys =
      if MapSet.member?(expanded_group_keys, key) do
        MapSet.delete(expanded_group_keys, key)
      else
        MapSet.put(expanded_group_keys, key)
      end

    {:noreply, assign(socket, expanded_group_keys: expanded_group_keys)}
  end

  @impl true
  def handle_info({:active_scene_updated, room_id, scene_id}, socket) do
    {:noreply,
     socket
     |> assign(
       active_scene_by_room:
         put_active_scene(socket.assigns.active_scene_by_room, room_id, scene_id)
     )
     |> close_selected_light_if_locked()}
  end

  def handle_info({:control_state, type, id, state}, socket)
      when type in [:light, :group] and is_integer(id) and is_map(state) do
    {:noreply,
     assign(socket, StateUpdates.replace_control_state(socket.assigns, type, id, state))}
  end

  def handle_info(_message, socket), do: {:noreply, socket}

  @impl true
  def render(assigns) do
    assigns = assign(assigns, control_target: selected_control_target(assigns))

    ~H"""
    <div class="hw-shell">
      <div class="hw-topbar">
        <div>
          <h1 class="hw-title">Control</h1>
          <p class="hw-subtitle">Room-centered scenes and recursive light control.</p>
        </div>
        <div class="hw-actions">
          <button class="hw-button" phx-click="refresh">Reload</button>
        </div>
      </div>

      <HueworksWeb.Layouts.app_flash_group flash={@flash} class="hw-flash-stack-inline" />

      <div class="hw-list">
        <%= for room_model <- @room_models do %>
          <section class="hw-card hw-control-room-card" id={"control-room-#{room_model.room.id}"}>
            <div class="hw-card-title">
              <div>
                <h3><%= display_name(room_model.room) %></h3>
                <p class="hw-meta">
                  <%= Enum.count(room_model.scenes) %> scenes · <%= Enum.count(room_model.lights) %> lights
                </p>
              </div>
              <div class="hw-actions">
                <button
                  type="button"
                  class="hw-button"
                  phx-click="toggle_room_power"
                  phx-value-room_id={room_model.room.id}
                  phx-value-action="on"
                >
                  All On
                </button>
                <button
                  type="button"
                  class="hw-button hw-button-off"
                  phx-click="toggle_room_power"
                  phx-value-room_id={room_model.room.id}
                  phx-value-action="off"
                >
                  All Off
                </button>
              </div>
            </div>

            <div class="hw-control-room-grid">
              <section class="hw-control-section">
                <div class="hw-room-scenes-header">
                  <p class="hw-room-label">Scenes</p>
                  <a class="hw-edit-button hw-add-scene-button" href={"/rooms/#{room_model.room.id}/scenes/new"} aria-label="Add scene">
                    <svg viewBox="0 0 24 24" aria-hidden="true" focusable="false">
                      <path d="M11 5h2v14h-2z"></path>
                      <path d="M5 11h14v2H5z"></path>
                    </svg>
                  </a>
                </div>
                <div class="hw-room-list">
                  <%= for scene <- room_model.scenes do %>
                    <% active? = Map.get(@active_scene_by_room, room_model.room.id) == scene.id %>
                    <div class="hw-room-item hw-room-item-row">
                      <span><%= display_name(scene) %></span>
                      <button
                        type="button"
                        class={if active?, do: "hw-button hw-button-off", else: "hw-button"}
                        phx-click="toggle_scene"
                        phx-value-id={scene.id}
                      >
                        <%= if active?, do: "Deactivate", else: "Activate" %>
                      </button>
                    </div>
                  <% end %>
                  <%= if room_model.scenes == [] do %>
                    <span class="hw-room-item hw-room-empty">No scenes yet</span>
                  <% end %>
                </div>
              </section>

              <section class="hw-control-section">
                <p class="hw-room-label">Lights</p>
                <div class="hw-room-list hw-group-tree">
                  <.group_node
                    :for={node <- room_model.topology.nodes}
                    node={node}
                    room={room_model.room}
                    lights={room_model.lights}
                    expanded_group_keys={@expanded_group_keys}
                    group_state={@group_state}
                    light_state={@light_state}
                    active_scene_by_room={@active_scene_by_room}
                  />

                  <.light_row
                    :for={light_id <- room_model.topology.ungrouped_light_ids}
                    light_id={light_id}
                    lights={room_model.lights}
                    light_state={@light_state}
                    active_scene_by_room={@active_scene_by_room}
                  />

                  <%= if room_model.topology.nodes == [] and room_model.topology.ungrouped_light_ids == [] do %>
                    <span class="hw-room-item hw-room-empty">No controllable lights</span>
                  <% end %>
                </div>
              </section>
            </div>
          </section>
        <% end %>
      </div>

      <.control_modal
        :if={@control_target}
        target={@control_target.target}
        target_type={@control_target.type}
        state_map={@control_target.state_map}
      />
    </div>
    """
  end

  defp group_node(assigns) do
    assigns =
      assign(assigns,
        expanded?:
          group_expanded?(
            assigns.expanded_group_keys,
            assigns.room.id,
            assigns.node.group_id
          ),
        control_available?:
          not Presentation.manual_adjustment_locked?(
            assigns.active_scene_by_room,
            assigns.node.group.room_id
          )
      )

    ~H"""
    <div class="hw-group-node" id={"control-room-#{@room.id}-group-#{@node.group_id}"}>
      <span class="hw-room-item hw-room-item-row hw-group-node-row">
        <button
          type="button"
          class="hw-group-toggle"
          phx-click="toggle_group_expanded"
          phx-value-room_id={@room.id}
          phx-value-group_id={@node.group_id}
          aria-expanded={@expanded?}
        >
          <%= if @expanded?, do: "-", else: "+" %>
          <%= display_name(@node.group) %>
          <span class="hw-muted">(<%= Enum.count(@node.total_light_ids) %> lights)</span>
        </button>
        <span class="hw-room-item-actions">
          <button
            type="button"
            class={power_button_class(@group_state, @node.group_id)}
            phx-click="toggle"
            phx-value-type="group"
            phx-value-id={@node.group_id}
          >
            On/Off
          </button>
          <button
            :if={@control_available?}
            type="button"
            class="hw-button"
            phx-click="open_group_control"
            phx-value-id={@node.group_id}
          >
            Control
          </button>
        </span>
      </span>

      <div :if={@expanded?} class="hw-group-node-body">
        <.group_node
          :for={child <- @node.children}
          node={child}
          room={@room}
          lights={@lights}
          expanded_group_keys={@expanded_group_keys}
          group_state={@group_state}
          light_state={@light_state}
          active_scene_by_room={@active_scene_by_room}
        />

        <div class="hw-group-node-lights">
          <.light_row
            :for={light_id <- @node.light_ids}
            id={"control-room-#{@room.id}-group-#{@node.group_id}-light-#{light_id}"}
            class="hw-group-light"
            light_id={light_id}
            lights={@lights}
            light_state={@light_state}
            active_scene_by_room={@active_scene_by_room}
          />
        </div>
      </div>
    </div>
    """
  end

  defp light_row(assigns) do
    assigns =
      assigns
      |> assign_new(:id, fn -> nil end)
      |> assign_new(:class, fn -> nil end)
      |> assign(:light, light_for_id(assigns.lights, assigns.light_id))

    assigns =
      assign(assigns,
        control_available?:
          assigns.light &&
            not Presentation.manual_adjustment_locked?(
              assigns.active_scene_by_room,
              assigns.light.room_id
            )
      )

    ~H"""
    <span id={@id} class={["hw-room-item hw-room-item-row", @class]}>
      <span><%= light_name(@lights, @light_id) %></span>
      <span class="hw-room-item-actions">
        <button
          type="button"
          class={power_button_class(@light_state, @light_id)}
          phx-click="toggle"
          phx-value-type="light"
          phx-value-id={@light_id}
        >
          On/Off
        </button>
        <button
          :if={@control_available?}
          type="button"
          class="hw-button"
          phx-click="open_light_control"
          phx-value-id={@light_id}
        >
          Control
        </button>
      </span>
    </span>
    """
  end

  defp control_modal(assigns) do
    type = Atom.to_string(assigns.target_type)

    assigns =
      assigns
      |> assign(
        :brightness,
        Presentation.state_value(assigns.state_map, assigns.target.id, :brightness, 75)
      )
      |> assign(:color_preview, Presentation.color_preview(assigns.state_map, assigns.target.id))
      |> assign(:target_type_string, type)

    ~H"""
    <div class="hw-modal-backdrop">
      <div
        class="hw-modal hw-control-modal"
        id={"control-#{@target_type_string}-modal-#{@target.id}"}
        phx-click-away="close_light_control"
      >
        <div class="hw-modal-header">
          <h3><%= display_name(@target) %></h3>
          <button
            type="button"
            class="hw-modal-close"
            phx-click="close_light_control"
            aria-label="Close"
          >
            ×
          </button>
        </div>

        <div class="hw-controls">
          <div class="hw-control-slider">
            <div class="hw-control-slider-label">
              <span>Brightness</span>
              <span id={"control-#{@target_type_string}-brightness-value-#{@target.id}"} class="hw-slider-value">
                <%= @brightness %>%
              </span>
            </div>
            <input
              id={"control-#{@target_type_string}-brightness-#{@target.id}"}
              type="range"
              min="1"
              max="100"
              value={@brightness}
              phx-hook="BrightnessSlider"
              data-type={@target_type_string}
              data-id={@target.id}
              data-output-id={"control-#{@target_type_string}-brightness-value-#{@target.id}"}
            />
          </div>

          <%= if @target.supports_temp do %>
            <div class="hw-control-slider">
              <% {min_k, max_k} = Hueworks.Kelvin.derive_range(@target) %>
              <% kelvin = Presentation.state_value(@state_map, @target.id, :kelvin, round((min_k + max_k) / 2)) %>
              <div class="hw-control-slider-label">
                <span>Temperature</span>
                <span id={"control-#{@target_type_string}-temp-value-#{@target.id}"} class="hw-slider-value">
                  <%= kelvin %>K
                </span>
              </div>
              <input
                id={"control-#{@target_type_string}-temp-#{@target.id}"}
                type="range"
                min={min_k}
                max={max_k}
                value={kelvin}
                phx-hook="TempSlider"
                data-type={@target_type_string}
                data-id={@target.id}
                data-output-id={"control-#{@target_type_string}-temp-value-#{@target.id}"}
              />
            </div>
          <% end %>

          <%= if @target.supports_color do %>
            <div class="hw-color-preview">
              <span
                class="hw-color-swatch"
                style={Presentation.color_preview_style(@state_map, @target.id)}
              >
              </span>
              <span class="hw-muted">
                <%= Presentation.color_preview_label(@state_map, @target.id) %>
              </span>
            </div>

            <div class="hw-control-slider">
              <div class="hw-control-slider-label">
                <span>Hue</span>
                <span id={"control-#{@target_type_string}-hue-value-#{@target.id}"} class="hw-slider-value">
                  <%= @color_preview.hue %>°
                </span>
              </div>
              <input
                id={"control-#{@target_type_string}-hue-#{@target.id}"}
                type="range"
                min="0"
                max="360"
                value={@color_preview.hue}
                phx-hook="ColorHueSlider"
                data-type={@target_type_string}
                data-id={@target.id}
                data-output-id={"control-#{@target_type_string}-hue-value-#{@target.id}"}
                data-hue-input-id={"control-#{@target_type_string}-hue-#{@target.id}"}
                data-saturation-input-id={"control-#{@target_type_string}-saturation-#{@target.id}"}
              />
            </div>
            <div class="hw-color-scale hw-hue-scale" aria-hidden="true"></div>

            <div class="hw-control-slider">
              <div class="hw-control-slider-label">
                <span>Saturation</span>
                <span id={"control-#{@target_type_string}-saturation-value-#{@target.id}"} class="hw-slider-value">
                  <%= @color_preview.saturation %>%
                </span>
              </div>
              <input
                id={"control-#{@target_type_string}-saturation-#{@target.id}"}
                type="range"
                min="0"
                max="100"
                value={@color_preview.saturation}
                phx-hook="ColorSaturationSlider"
                data-type={@target_type_string}
                data-id={@target.id}
                data-output-id={"control-#{@target_type_string}-saturation-value-#{@target.id}"}
                data-hue-input-id={"control-#{@target_type_string}-hue-#{@target.id}"}
                data-saturation-input-id={"control-#{@target_type_string}-saturation-#{@target.id}"}
              />
            </div>
            <div
              class="hw-color-scale"
              style={Presentation.color_saturation_scale_style(@state_map, @target.id)}
              aria-hidden="true"
            >
            </div>
          <% end %>
        </div>
      </div>
    </div>
    """
  end

  defp control_assigns do
    rooms = Rooms.list_rooms_with_children()
    groups = Groups.list_controllable_groups()
    lights = Lights.list_controllable_lights()
    groups = attach_group_light_ids(groups)

    %{
      room_models: room_models(rooms, groups, lights),
      rooms: rooms,
      groups: groups,
      lights: lights,
      active_scene_by_room: active_scene_by_room(),
      group_state: DisplayState.build_group_state(groups),
      light_state: DisplayState.build_light_state(lights)
    }
  end

  defp room_models(rooms, groups, lights) do
    Enum.map(rooms, fn room ->
      room_groups = Enum.filter(groups, &(&1.room_id == room.id))
      room_lights = Enum.filter(lights, &(&1.room_id == room.id))
      visible_light_ids = MapSet.new(Enum.map(room_lights, & &1.id))

      topology_light_ids =
        room_groups
        |> Enum.flat_map(& &1.light_ids)
        |> Kernel.++(MapSet.to_list(visible_light_ids))
        |> Enum.uniq()

      %{
        room: room,
        scenes: Enum.sort_by(room.scenes, &String.downcase(display_name(&1))),
        groups: room_groups,
        lights: room_lights,
        topology:
          room_groups
          |> Topology.presentation_tree(topology_light_ids)
          |> filter_topology_lights(visible_light_ids)
      }
    end)
  end

  defp attach_group_light_ids(groups) do
    group_ids = Enum.map(groups, & &1.id)
    light_ids_by_group = light_ids_by_group(group_ids)

    Enum.map(groups, fn group ->
      group
      |> Map.from_struct()
      |> Map.put(:light_ids, Map.get(light_ids_by_group, group.id, []))
    end)
  end

  defp light_ids_by_group([]), do: %{}

  defp light_ids_by_group(group_ids) do
    Repo.all(
      from(gl in GroupLight,
        where: gl.group_id in ^group_ids,
        select: {gl.group_id, gl.light_id}
      )
    )
    |> Enum.group_by(fn {group_id, _light_id} -> group_id end, fn {_group_id, light_id} ->
      light_id
    end)
  end

  defp filter_topology_lights(topology, visible_light_ids) do
    %{
      topology
      | nodes: Enum.map(topology.nodes, &filter_topology_node(&1, visible_light_ids)),
        ungrouped_light_ids:
          filter_visible_light_ids(topology.ungrouped_light_ids, visible_light_ids)
    }
  end

  defp filter_topology_node(node, visible_light_ids) do
    %{
      node
      | children: Enum.map(node.children, &filter_topology_node(&1, visible_light_ids)),
        light_ids: filter_visible_light_ids(node.light_ids, visible_light_ids)
    }
  end

  defp filter_visible_light_ids(light_ids, visible_light_ids) do
    Enum.filter(light_ids, &MapSet.member?(visible_light_ids, &1))
  end

  defp update_room_control_state(assigns, room_model, attrs) do
    light_state =
      Enum.reduce(room_model.lights, assigns.light_state, fn light, acc ->
        Map.update(acc, light.id, attrs, &DisplayState.merge_light(&1, light, attrs))
      end)

    group_state =
      Enum.reduce(room_model.groups, assigns.group_state, fn group, acc ->
        Map.update(acc, group.id, attrs, &DisplayState.merge(&1, attrs))
      end)

    %{light_state: light_state, group_state: group_state, status: nil}
  end

  defp room_model(room_models, room_id) do
    Enum.find(room_models, &(&1.room.id == room_id))
  end

  defp active_scene_by_room do
    ActiveScenes.list_active_scenes()
    |> Map.new(fn active_scene -> {active_scene.room_id, active_scene.scene_id} end)
  end

  defp put_active_scene(active_scene_by_room, room_id, scene_id) when is_integer(room_id) do
    case scene_id do
      value when is_integer(value) -> Map.put(active_scene_by_room || %{}, room_id, value)
      _ -> Map.delete(active_scene_by_room || %{}, room_id)
    end
  end

  defp scene_activation_trace(room_id, current_active, scene_id) do
    %{
      trace_id: "control-scene-#{room_id}-#{System.unique_integer([:positive])}",
      source: "control_live.scene",
      room_id: room_id,
      previous_scene_id: Map.get(current_active || %{}, :scene_id),
      scene_id: scene_id,
      started_at_ms: System.monotonic_time(:millisecond)
    }
  end

  defp parse_power_action("on"), do: :on
  defp parse_power_action("off"), do: :off
  defp parse_power_action(_action), do: nil

  defp manual_adjustment_request(
         "set_brightness",
         %{"type" => type, "id" => id, "level" => level}
       ),
       do: {:ok, {type, id, {:brightness, level}}}

  defp manual_adjustment_request(
         "set_color_temp",
         %{"type" => type, "id" => id, "kelvin" => kelvin}
       ),
       do: {:ok, {type, id, {:color_temp, kelvin}}}

  defp manual_adjustment_request(
         "set_color",
         %{"type" => type, "id" => id, "hue" => hue, "saturation" => saturation}
       ),
       do: {:ok, {type, id, {:color, hue, saturation}}}

  defp manual_adjustment_request(_event, _params), do: {:error, "Invalid light control"}

  defp close_selected_light_if_locked(socket) do
    case selected_control_target(socket.assigns) do
      nil ->
        socket

      %{target: target} ->
        if manual_adjustment_locked?(socket.assigns, target) do
          assign(socket, selected_control_target: nil)
        else
          socket
        end
    end
  end

  defp selected_control_target(%{selected_control_target: {type, id}} = assigns) do
    case control_target(assigns, type, id) do
      nil ->
        nil

      target ->
        %{
          type: type,
          target: target,
          state_map: state_map_for_type(assigns, type)
        }
    end
  end

  defp selected_control_target(_assigns), do: nil

  defp control_target_type("light"), do: :light
  defp control_target_type("group"), do: :group
  defp control_target_type(type) when type in [:light, :group], do: type
  defp control_target_type(_type), do: nil

  defp control_target(assigns, :light, id) do
    Enum.find(Map.get(assigns, :lights, []), &(&1.id == id))
  end

  defp control_target(assigns, :group, id) do
    Enum.find(Map.get(assigns, :groups, []), &(&1.id == id))
  end

  defp control_target(_assigns, _type, _id), do: nil

  defp state_map_for_type(assigns, :light), do: assigns.light_state
  defp state_map_for_type(assigns, :group), do: assigns.group_state

  defp manual_adjustment_locked?(assigns, target) do
    Presentation.manual_adjustment_locked?(assigns.active_scene_by_room, target.room_id)
  end

  defp maybe_put_status_flash(socket) do
    case socket.assigns[:status] do
      status when is_binary(status) ->
        socket
        |> assign(:status, nil)
        |> put_notice(:info, status)

      _ ->
        socket
    end
  end

  defp put_notice(socket, :info, message) when is_binary(message) do
    socket
    |> clear_flash(:error)
    |> put_flash(:info, message)
  end

  defp put_notice(socket, :error, message) when is_binary(message) do
    socket
    |> clear_flash(:info)
    |> put_flash(:error, message)
  end

  defp power_button_class(state_map, id) do
    if powered_on?(state_map, id), do: "hw-button hw-button-on", else: "hw-button hw-button-off"
  end

  defp powered_on?(state_map, id) do
    case Map.get(state_map, id, %{}) do
      %{power: power} when power in [:on, "on", true] -> true
      _ -> false
    end
  end

  defp group_expanded?(expanded_group_keys, room_id, group_id) do
    expanded_group_keys
    |> MapSet.member?(group_expanded_key(room_id, group_id))
  end

  defp group_expanded_key(room_id, group_id), do: "#{room_id}:#{group_id}"

  defp display_name(entity), do: Util.display_name(entity)

  defp light_name(lights, id) do
    lights
    |> light_for_id(id)
    |> display_name()
  end

  defp light_for_id(lights, id) do
    Enum.find(lights, &(&1.id == id))
  end
end
