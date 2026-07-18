defmodule HueworksWeb.SetupLive do
  use Phoenix.LiveView

  import HueworksWeb.Notices

  alias Hueworks.{Areas, Bridges, ExternalSpaces, Onboarding, Util}
  alias Hueworks.HomeAssistant.Inventory
  alias Hueworks.Onboarding.AreaDesign
  alias Hueworks.Schemas.Bridge

  def mount(_params, _session, socket) do
    {:ok, load_setup(socket)}
  end

  def handle_event("choose_path", %{"path" => path}, socket) do
    with {:ok, parsed} <- parse_path(path),
         {:ok, _settings} <- Onboarding.choose_path(parsed) do
      {:noreply, socket |> assign(path_choice_open?: false) |> load_setup()}
    else
      _ -> {:noreply, put_notice(socket, :error, "Choose a supported setup path.")}
    end
  end

  def handle_event("change_path", _params, socket) do
    {:noreply, assign(socket, path_choice_open?: true)}
  end

  def handle_event("refresh_ha_inventory", %{"bridge_id" => bridge_id}, socket) do
    with bridge_id when is_integer(bridge_id) <- Util.parse_id(bridge_id),
         %Bridge{type: :ha} = bridge <- Bridges.get_bridge(bridge_id) do
      {:noreply,
       socket
       |> assign(inventory_refreshing_id: bridge.id)
       |> start_async({:refresh_ha_inventory, bridge.id}, fn ->
         pipeline_module().create_import(bridge)
       end)}
    else
      _ -> {:noreply, put_notice(socket, :error, "Home Assistant bridge not found.")}
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
       |> load_setup()
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
       |> load_setup()
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
       |> load_setup()
       |> put_notice(:info, "Left this Home Assistant Floor unmapped.")}
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
       |> load_setup()
       |> put_notice(:info, "External space mapping saved.")}
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
       |> load_setup()
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
       |> load_setup()
       |> put_notice(:info, "Left this external space unmapped.")}
    else
      _ -> {:noreply, put_notice(socket, :error, "External space not found.")}
    end
  end

  def handle_event("finish_setup", _params, socket) do
    case Onboarding.finish() do
      {:ok, _settings} ->
        {:noreply, push_navigate(socket, to: "/control")}

      {:error, _changeset} ->
        {:noreply, put_notice(socket, :error, "Setup could not be finished.")}
    end
  end

  def handle_event("dismiss_setup", _params, socket) do
    case Onboarding.dismiss() do
      {:ok, _settings} ->
        {:noreply, push_navigate(socket, to: "/config")}

      {:error, _changeset} ->
        {:noreply, put_notice(socket, :error, "Setup could not be dismissed.")}
    end
  end

  def handle_async({:refresh_ha_inventory, bridge_id}, {:ok, {:ok, _bridge_import}}, socket) do
    bridge = Bridges.get_bridge(bridge_id)
    _ = AreaDesign.refresh(bridge)

    {:noreply,
     socket
     |> assign(inventory_refreshing_id: nil)
     |> load_setup()
     |> put_notice(:info, "Home Assistant inventory refreshed. No entities were imported.")}
  end

  def handle_async({:refresh_ha_inventory, _bridge_id}, {:ok, {:error, reason}}, socket) do
    {:noreply,
     socket
     |> assign(inventory_refreshing_id: nil)
     |> put_notice(:error, "Home Assistant inventory failed: #{operation_error(reason)}")}
  end

  def handle_async({:refresh_ha_inventory, _bridge_id}, {:exit, reason}, socket) do
    {:noreply,
     socket
     |> assign(inventory_refreshing_id: nil)
     |> put_notice(:error, "Home Assistant inventory failed: #{operation_error(reason)}")}
  end

  defp load_setup(socket) do
    status = Onboarding.status()
    bridges = Bridges.list_bridges() |> Enum.sort_by(&{&1.type, &1.name})
    ha_entries = bridges |> Enum.filter(&(&1.type == :ha)) |> Enum.map(&ha_entry/1)
    native_bridges = Enum.reject(bridges, &(&1.type == :ha))

    assign(socket,
      status: status,
      path_choice_open?: Map.get(socket.assigns, :path_choice_open?, false),
      inventory_refreshing_id: Map.get(socket.assigns, :inventory_refreshing_id),
      bridges: bridges,
      ha_entries: ha_entries,
      native_bridges: native_bridges,
      steps: setup_steps(status, ha_entries, native_bridges),
      areas: Areas.list_areas()
    )
  end

  defp ha_entry(bridge) do
    case Inventory.latest(bridge) do
      {:ok, inventory} ->
        {:ok, design} = AreaDesign.refresh(bridge)
        %{bridge: bridge, inventory: inventory, design: design}

      {:error, :inventory_not_fetched} ->
        %{bridge: bridge, inventory: nil, design: nil}
    end
  end

  defp setup_steps(status, ha_entries, native_bridges) do
    common = [
      step("location", "Set location", status.location_configured?, "/config/general"),
      step("areas", "Create Areas", status.area_count > 0, "/areas"),
      step(
        "native",
        "Import native bridges",
        native_imported?(native_bridges),
        "/config/bridges"
      ),
      step("placement", "Review final placement", placement_reviewed?(status), "/lights"),
      step("scene", "Create and preview a scene", status.scene_count > 0, "/areas")
    ]

    if status.path == :ha_assisted do
      [
        step("ha", "Connect Home Assistant", ha_entries != [], "/config/bridges/new?type=ha"),
        step(
          "inventory",
          "Review Home Assistant inventory",
          inventory_fetched?(ha_entries),
          "/setup"
        )
        | common
      ] ++
        [
          step(
            "ha-only",
            "Import selected HA-only entities last",
            ha_entities_imported?(ha_entries),
            "/config/bridges"
          ),
          step("exports", "Configure optional exports", true, "/config/integrations",
            optional?: true
          )
        ]
    else
      common
    end
  end

  defp step(id, title, complete?, href, opts \\ []) do
    %{id: id, title: title, complete?: complete?, href: href, optional?: opts[:optional] == true}
  end

  defp native_imported?([]), do: false
  defp native_imported?(bridges), do: Enum.all?(bridges, &Bridges.imported?/1)

  defp inventory_fetched?(entries),
    do: entries != [] and Enum.all?(entries, &(not is_nil(&1.inventory)))

  defp ha_entities_imported?([]), do: false
  defp ha_entities_imported?(entries), do: Enum.all?(entries, &Bridges.imported?(&1.bridge))

  defp placement_reviewed?(status) do
    status.light_count + status.group_count > 0 and status.area_count > 0
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

  defp parse_path("ha_assisted"), do: {:ok, :ha_assisted}
  defp parse_path("direct"), do: {:ok, :direct}
  defp parse_path(_path), do: {:error, :invalid_path}

  defp operation_error(%Ecto.Changeset{}), do: "the requested values were not valid"
  defp operation_error(reason) when is_binary(reason), do: reason

  defp operation_error(reason) when is_atom(reason),
    do: reason |> Atom.to_string() |> String.replace("_", " ")

  defp operation_error(_reason), do: "unexpected error"

  defp pipeline_module,
    do: Application.get_env(:hueworks, :onboarding_import_pipeline, Hueworks.Import.Pipeline)

  def count_label(count, singular) when is_integer(count) do
    label =
      case {count, singular} do
        {1, value} ->
          value

        {_, value} when value in ["entity", "relevant entity", "HA-only entity"] ->
          String.replace_suffix(value, "entity", "entities")

        {_, value} ->
          value <> "s"
      end

    "#{count} #{label}"
  end

  def source_label(:hue), do: "Hue"
  def source_label(:caseta), do: "Caseta"
  def source_label(:z2m), do: "Zigbee2MQTT"
  def source_label(source), do: to_string(source)

  def area_name(%{mapping: %{area: area}}) when not is_nil(area), do: Util.display_name(area)
  def area_name(_space), do: nil

  attr(:entry, :map, required: true)
  attr(:item, :map, required: true)
  attr(:areas, :list, required: true)

  def space_row(assigns) do
    ~H"""
    <article class="hw-source-space-row" id={"ha-area-#{@entry.bridge.id}-#{@item.space.external_id}"}>
      <div class="hw-source-space-copy">
        <strong><%= @item.space.name %></strong>
        <span class="hw-meta"><%= count_label(@item.entity_count, "relevant entity") %></span>
        <span :if={area_name(@item.space)} class="hw-status-badge hw-status-badge-success">
          Mapped to <%= area_name(@item.space) %>
        </span>
      </div>

      <form
        id={"map-space-#{@entry.bridge.id}-#{@item.space.external_id}"}
        class="hw-inline-form hw-space-map-form"
        phx-submit="map_space"
      >
        <input type="hidden" name="bridge_id" value={@entry.bridge.id} />
        <input type="hidden" name="kind" value={@item.space.kind} />
        <input type="hidden" name="external_id" value={@item.space.external_id} />
        <select name="target_area_id" class="hw-select" aria-label={"Destination for #{@item.space.name}"}>
          <option value="">Map to an existing Area</option>
          <option
            :for={area <- @areas}
            value={area.id}
            selected={area_name(@item.space) && @item.space.mapping.area_id == area.id}
          >
            <%= Util.display_name(area) %>
          </option>
        </select>
        <button type="submit" class="hw-button hw-button-small">Map</button>
      </form>

      <form class="hw-inline-form hw-space-create-form" phx-submit="create_area_for_space">
        <input type="hidden" name="bridge_id" value={@entry.bridge.id} />
        <input type="hidden" name="kind" value={@item.space.kind} />
        <input type="hidden" name="external_id" value={@item.space.external_id} />
        <input class="hw-field-input" name="name" value={@item.space.name} aria-label={"New Area for #{@item.space.name}"} />
        <button type="submit" class="hw-button hw-button-small">Create Area</button>
      </form>

      <button
        type="button"
        class="hw-button hw-button-small hw-button-quiet"
        phx-click="skip_space"
        phx-value-bridge_id={@entry.bridge.id}
        phx-value-kind={@item.space.kind}
        phx-value-external_id={@item.space.external_id}
      >
        Skip
      </button>
    </article>
    """
  end
end
