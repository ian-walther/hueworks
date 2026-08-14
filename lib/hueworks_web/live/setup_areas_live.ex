defmodule HueworksWeb.SetupAreasLive do
  use Phoenix.LiveView

  import HueworksWeb.SetupHelpers
  import HueworksWeb.Notices

  alias Hueworks.{Areas, Bridges, ExternalSpaces, Util}
  alias Hueworks.Onboarding.AreaDesign
  alias Hueworks.Schemas.Bridge

  def mount(_params, _session, socket) do
    socket = assign_new(socket, :design_refresh_errors, fn -> %{} end)

    if connected?(socket) do
      {:ok, socket |> refresh_designs() |> load_design()}
    else
      {:ok, load_design(socket)}
    end
  end

  def handle_event("retry_design", %{"bridge_id" => bridge_id}, socket) do
    with bridge_id when is_integer(bridge_id) <- Util.parse_id(bridge_id),
         %Bridge{type: :ha} = bridge <- Bridges.get_bridge(bridge_id) do
      {:noreply, socket |> refresh_design(bridge) |> load_design()}
    else
      _other -> {:noreply, put_notice(socket, :error, "Home Assistant bridge not found.")}
    end
  end

  def handle_event("use_floor_one", params, socket) do
    with {:ok, bridge, external_id} <- bridge_space(params, "ha_floor"),
         name when name != "" <- normalized_name(params["name"]),
         {:ok, area} <- AreaDesign.use_floor_as_one_area(bridge, external_id, %{name: name}),
         floor when not is_nil(floor) <-
           ExternalSpaces.get_by_identity(bridge, "ha_floor", external_id) do
      {:noreply,
       socket
       |> load_design()
       |> put_notice(:info, "Mapped #{floor.name} and its HA Areas to #{area.name}.")}
    else
      nil -> {:noreply, put_notice(socket, :error, "Home Assistant Floor not found.")}
      "" -> {:noreply, put_notice(socket, :error, "Enter a HueWorks Area name.")}
      {:error, reason} -> {:noreply, put_notice(socket, :error, operation_error(reason))}
    end
  end

  def handle_event("use_floor_separate", params, socket) do
    with {:ok, bridge, external_id} <- bridge_space(params, "ha_floor"),
         {:ok, areas} <- AreaDesign.use_floor_areas_separately(bridge, external_id) do
      {:noreply,
       socket
       |> load_design()
       |> put_notice(:info, "Created and mapped #{length(areas)} HueWorks Areas.")}
    else
      {:error, reason} -> {:noreply, put_notice(socket, :error, operation_error(reason))}
    end
  end

  def handle_event("skip_floor", params, socket) do
    with {:ok, bridge, external_id} <- bridge_space(params, "ha_floor"),
         :ok <- AreaDesign.skip_floor(bridge, external_id) do
      {:noreply,
       socket
       |> load_design()
       |> put_notice(:info, "Saved this Home Assistant Floor as intentionally ignored.")}
    else
      {:error, reason} -> {:noreply, put_notice(socket, :error, operation_error(reason))}
    end
  end

  def handle_event("map_space", params, socket) do
    with {:ok, bridge, kind, external_id} <- bridge_space(params),
         area_id when is_integer(area_id) <- Util.parse_id(params["target_area_id"]),
         {:ok, _mapping} <- AreaDesign.map_space(bridge, kind, external_id, area_id) do
      {:noreply,
       socket
       |> keep_parent_floor_open(bridge, kind, external_id)
       |> load_design()
       |> put_notice(:info, "Area mapping saved.")}
    else
      _ -> {:noreply, put_notice(socket, :error, "Choose a valid HueWorks Area.")}
    end
  end

  def handle_event("create_area_for_space", params, socket) do
    with {:ok, bridge, kind, external_id} <- bridge_space(params),
         name when name != "" <- normalized_name(params["name"]),
         {:ok, _area} <- AreaDesign.create_and_map_space(bridge, kind, external_id, %{name: name}) do
      {:noreply,
       socket
       |> keep_parent_floor_open(bridge, kind, external_id)
       |> load_design()
       |> put_notice(:info, "HueWorks Area created and mapped.")}
    else
      _ -> {:noreply, put_notice(socket, :error, "Enter a valid HueWorks Area name.")}
    end
  end

  def handle_event("skip_space", params, socket) do
    with {:ok, bridge, kind, external_id} <- bridge_space(params),
         :ok <- AreaDesign.skip_space(bridge, kind, external_id) do
      {:noreply,
       socket
       |> keep_parent_floor_open(bridge, kind, external_id)
       |> load_design()
       |> put_notice(:info, "Saved this HA Area as intentionally ignored.")}
    else
      _ -> {:noreply, put_notice(socket, :error, "External space not found.")}
    end
  end

  defp load_design(socket) do
    socket = assign_new(socket, :open_floor_customizer_ids, fn -> MapSet.new() end)

    entries =
      Bridges.list_bridges()
      |> Enum.filter(&(&1.type == :ha))
      |> Enum.sort_by(& &1.name)
      |> Enum.map(&design_entry(&1, socket.assigns.design_refresh_errors))

    progress =
      Enum.reduce(entries, %{resolved: 0, total: 0}, fn
        %{design: design}, acc when not is_nil(design) ->
          %{
            resolved: acc.resolved + design.progress.resolved,
            total: acc.total + design.progress.total
          }

        _entry, acc ->
          acc
      end)

    assign(socket,
      entries: entries,
      areas: Areas.list_areas(),
      progress: progress,
      complete?: progress.total > 0 and progress.resolved == progress.total
    )
  end

  defp design_entry(bridge, errors) do
    case Map.fetch(errors, bridge.id) do
      {:ok, reason} ->
        %{bridge: bridge, design: nil, error: reason}

      :error ->
        if Bridges.latest_import(bridge) do
          %{bridge: bridge, design: area_design_module().design(bridge), error: nil}
        else
          %{bridge: bridge, design: nil, error: nil}
        end
    end
  end

  defp refresh_designs(socket) do
    Bridges.list_bridges()
    |> Enum.filter(&(&1.type == :ha))
    |> Enum.reduce(socket, &refresh_design(&2, &1))
  end

  defp refresh_design(socket, bridge) do
    case area_design_module().refresh(bridge) do
      {:ok, _design} ->
        update(socket, :design_refresh_errors, &Map.delete(&1, bridge.id))

      {:error, :inventory_not_fetched} ->
        update(socket, :design_refresh_errors, &Map.delete(&1, bridge.id))

      {:error, reason} ->
        update(socket, :design_refresh_errors, &Map.put(&1, bridge.id, reason))
    end
  end

  defp area_design_module do
    Application.get_env(
      :hueworks,
      :onboarding_area_design_module,
      AreaDesign
    )
  end

  defp bridge_space(params, expected_kind) do
    with {:ok, bridge, kind, external_id} <- bridge_space(Map.put(params, "kind", expected_kind)),
         true <- kind == expected_kind do
      {:ok, bridge, external_id}
    else
      _ -> {:error, :not_found}
    end
  end

  defp bridge_space(params) do
    with bridge_id when is_integer(bridge_id) <- Util.parse_id(params["bridge_id"]),
         %Bridge{} = bridge <- Bridges.get_bridge(bridge_id),
         kind when is_binary(kind) and kind != "" <- params["kind"],
         external_id when is_binary(external_id) and external_id != "" <- params["external_id"] do
      {:ok, bridge, kind, external_id}
    else
      _ -> {:error, :not_found}
    end
  end

  defp normalized_name(name) when is_binary(name), do: String.trim(name)
  defp normalized_name(_name), do: ""

  defp keep_parent_floor_open(socket, bridge, "ha_area", external_id) do
    case ExternalSpaces.get_by_identity(bridge, "ha_area", external_id) do
      %{parent_external_space_id: parent_id} when is_integer(parent_id) ->
        update(socket, :open_floor_customizer_ids, &MapSet.put(&1, parent_id))

      _space ->
        socket
    end
  end

  defp keep_parent_floor_open(socket, _bridge, _kind, _external_id), do: socket

  def progress_percent(%{total: 0}), do: 0
  def progress_percent(%{resolved: resolved, total: total}), do: round(resolved / total * 100)

  def area_name(%{mapping: %{area: area}}) when not is_nil(area),
    do: Util.display_name(area)

  def area_name(_space), do: nil

  def resolution_label(%{resolution: :mapped, space: space}),
    do: "Mapped to #{area_name(space)}"

  def resolution_label(%{resolution: :ignored}), do: "Ignored"
  def resolution_label(_entry), do: "Needs a decision"

  def floor_resolution_label(%{resolution: :mapped, space: space}),
    do: "Combined into #{area_name(space)}"

  def floor_resolution_label(%{resolution: :ignored, children: children}) do
    cond do
      Enum.all?(children, &(&1.resolution == :ignored)) -> "Floor ignored"
      Enum.all?(children, &(&1.resolution == :mapped)) -> "Areas handled separately"
      true -> "Areas handled individually"
    end
  end

  def floor_resolution_label(_floor), do: "Needs a decision"

  def space_names(items) do
    items
    |> Enum.map_join(", ", & &1.space.name)
    |> case do
      "" -> "No HA Areas in this Floor"
      names -> names
    end
  end

  attr(:entry, :map, required: true)
  attr(:floor, :map, required: true)
  attr(:areas, :list, required: true)
  attr(:completed, :boolean, default: false)
  attr(:open, :boolean, default: false)

  def floor_editor(assigns) do
    assigns =
      assign(assigns,
        pending_children: Enum.filter(assigns.floor.children, &(&1.resolution == :pending)),
        resolved_children: Enum.reject(assigns.floor.children, &(&1.resolution == :pending))
      )

    ~H"""
    <article
      id={"ha-floor-#{@entry.bridge.id}-#{@floor.space.external_id}"}
      class={["hw-card hw-floor-design-card", @completed && "hw-floor-design-card-complete"]}
    >
      <header class="hw-floor-design-header">
        <div>
          <p class="hw-eyebrow">HA Floor</p>
          <h3><%= @floor.space.name %></h3>
          <p class="hw-meta">
            <%= count_label(@floor.entity_count, "relevant entity") %> across
            <%= count_label(length(@floor.children), "HA area") %>
          </p>
          <p class="hw-floor-space-names"><%= space_names(@floor.children) %></p>
        </div>
        <span class={["hw-status-badge", @completed && "hw-status-badge-success"]}>
          <%= floor_resolution_label(@floor) %>
        </span>
      </header>

      <div class="hw-floor-primary-paths">
        <form phx-submit="use_floor_one" class="hw-floor-path-card hw-floor-path-card-featured">
          <input type="hidden" name="bridge_id" value={@entry.bridge.id} />
          <input type="hidden" name="external_id" value={@floor.space.external_id} />
          <div>
            <p class="hw-eyebrow">Coordinate together</p>
            <h4>Combine into one HueWorks Area</h4>
            <p class="hw-meta">Every HA Area on this Floor will share scenes and controls in one HueWorks Area.</p>
          </div>
          <%= if mapped_name = area_name(@floor.space) do %>
            <div class="hw-callout hw-callout-accent">
              <strong>Mapped HueWorks Area</strong>
              <span><%= mapped_name %></span>
            </div>
            <input type="hidden" name="name" value={mapped_name} />
            <button class="hw-button hw-button-primary" type="submit">
              Keep as <%= mapped_name %>
            </button>
          <% else %>
            <label class="hw-field-label" for={"floor-area-name-#{@entry.bridge.id}-#{@floor.space.external_id}"}>
              HueWorks Area name
            </label>
            <input
              id={"floor-area-name-#{@entry.bridge.id}-#{@floor.space.external_id}"}
              class="hw-field-input"
              name="name"
              value={@floor.space.name}
            />
            <button class="hw-button hw-button-primary" type="submit">Combine into one Area</button>
          <% end %>
        </form>

        <div class="hw-floor-path-card">
          <div>
            <p class="hw-eyebrow">Preserve boundaries</p>
            <h4>Keep HA Areas separate</h4>
            <p class="hw-meta">
              Create <%= count_label(length(@floor.children), "HueWorks Area") %> using the existing
              HA Area boundaries.
            </p>
          </div>
          <button
            class="hw-button"
            type="button"
            phx-click="use_floor_separate"
            phx-value-bridge_id={@entry.bridge.id}
            phx-value-external_id={@floor.space.external_id}
          >
            Create <%= length(@floor.children) %> separate Areas
          </button>
        </div>
      </div>

      <details
        id={"customize-floor-#{@entry.bridge.id}-#{@floor.space.external_id}"}
        class="hw-floor-customizer"
        open={@open}
      >
        <summary>
          <span class="hw-floor-customizer-copy">
            <strong>Customize individual Areas</strong>
            <span>Mix existing Areas, new Areas, and intentionally ignored HA Areas.</span>
          </span>
          <span class="hw-status-badge">Advanced</span>
        </summary>
        <div class="hw-floor-customizer-body">
          <div :if={@pending_children != []} class="hw-source-space-list">
            <.space_row :for={child <- @pending_children} entry={@entry} item={child} areas={@areas} />
          </div>
          <details :if={@resolved_children != []} class="hw-completed-subdecisions">
            <summary><%= count_label(length(@resolved_children), "completed child decision") %></summary>
            <div class="hw-source-space-list">
              <.space_row :for={child <- @resolved_children} entry={@entry} item={child} areas={@areas} />
            </div>
          </details>
        </div>
      </details>

      <div class="hw-floor-ignore-row">
        <span>
          <strong>Nothing from this Floor?</strong>
          Save the Floor and every HA Area inside it as intentionally ignored.
        </span>
        <button
          class="hw-button hw-button-quiet"
          type="button"
          phx-click="skip_floor"
          phx-value-bridge_id={@entry.bridge.id}
          phx-value-external_id={@floor.space.external_id}
        >
          Ignore entire Floor
        </button>
      </div>
    </article>
    """
  end

  attr(:entry, :map, required: true)
  attr(:item, :map, required: true)
  attr(:areas, :list, required: true)

  def space_row(assigns) do
    ~H"""
    <article class="hw-source-space-row" id={"ha-area-#{@entry.bridge.id}-#{@item.space.external_id}"}>
      <header class="hw-source-space-copy">
        <div>
          <p class="hw-eyebrow">HA Area</p>
          <h4><%= @item.space.name %></h4>
          <span class="hw-meta"><%= count_label(@item.entity_count, "relevant entity") %></span>
        </div>
        <span class={["hw-status-badge", @item.resolution != :pending && "hw-status-badge-success"]}>
          <%= resolution_label(@item) %>
        </span>
      </header>

      <div class="hw-space-action-grid">
        <form class="hw-space-action-card hw-space-create-form" phx-submit="create_area_for_space">
          <input type="hidden" name="bridge_id" value={@entry.bridge.id} />
          <input type="hidden" name="kind" value={@item.space.kind} />
          <input type="hidden" name="external_id" value={@item.space.external_id} />
          <div>
            <strong>Create a matching Area</strong>
            <p class="hw-meta">Make a new HueWorks Area for this HA Area.</p>
          </div>
          <label class="hw-field-label" for={"new-area-#{@entry.bridge.id}-#{@item.space.external_id}"}>New Area name</label>
          <input
            id={"new-area-#{@entry.bridge.id}-#{@item.space.external_id}"}
            class="hw-field-input"
            name="name"
            value={@item.space.name}
          />
          <button type="submit" class="hw-button hw-button-small">Create and use</button>
        </form>

        <form
          id={"map-space-#{@entry.bridge.id}-#{@item.space.external_id}"}
          class="hw-space-action-card hw-space-map-form"
          phx-submit="map_space"
        >
          <input type="hidden" name="bridge_id" value={@entry.bridge.id} />
          <input type="hidden" name="kind" value={@item.space.kind} />
          <input type="hidden" name="external_id" value={@item.space.external_id} />
          <div>
            <strong>Use an existing Area</strong>
            <p class="hw-meta">Coordinate this HA Area with an Area you already created.</p>
          </div>
          <label class="hw-field-label" for={"existing-area-#{@entry.bridge.id}-#{@item.space.external_id}"}>HueWorks Area</label>
          <select
            id={"existing-area-#{@entry.bridge.id}-#{@item.space.external_id}"}
            name="target_area_id"
            class="hw-select"
            aria-label={"Destination for #{@item.space.name}"}
          >
            <option value="">Choose an existing Area</option>
            <option
              :for={area <- @areas}
              value={area.id}
              selected={area_name(@item.space) && @item.space.mapping.area_id == area.id}
            >
              <%= Util.display_name(area) %>
            </option>
          </select>
          <button type="submit" class="hw-button hw-button-small">Use selected Area</button>
        </form>

        <div class="hw-space-action-card hw-space-ignore-action">
          <div>
            <strong>Ignore this HA Area</strong>
            <p class="hw-meta">Save that HueWorks should not create or choose a destination.</p>
          </div>
          <button
            type="button"
            class="hw-button hw-button-small hw-button-quiet"
            phx-click="skip_space"
            phx-value-bridge_id={@entry.bridge.id}
            phx-value-kind={@item.space.kind}
            phx-value-external_id={@item.space.external_id}
          >
            Ignore Area
          </button>
        </div>
      </div>
    </article>
    """
  end
end
