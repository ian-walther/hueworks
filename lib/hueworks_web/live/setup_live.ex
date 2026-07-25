defmodule HueworksWeb.SetupLive do
  use Phoenix.LiveView

  import HueworksWeb.SetupHelpers
  import HueworksWeb.Notices

  alias Hueworks.{Bridges, Onboarding, Util}
  alias Hueworks.HomeAssistant.Inventory
  alias Hueworks.Onboarding.AreaDesign
  alias Hueworks.Schemas.Bridge

  def mount(params, _session, socket) do
    socket = load_setup(socket)

    if connected?(socket) do
      {:ok, maybe_continue_ha_inventory(socket, params)}
    else
      {:ok, socket}
    end
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
      {:noreply, start_inventory_refresh(socket, bridge, :stay)}
    else
      _ -> {:noreply, put_notice(socket, :error, "Home Assistant bridge not found.")}
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
    if MapSet.member?(socket.assigns.inventory_refreshing_ids, bridge_id) do
      bridge = Bridges.get_bridge(bridge_id)
      _ = AreaDesign.refresh(bridge)
      destination = Map.get(socket.assigns.inventory_refresh_destinations, bridge_id)

      socket =
        socket
        |> finish_inventory_refresh(bridge_id)
        |> load_setup()
        |> put_notice(:info, "Home Assistant inventory refreshed. No entities were imported.")

      if destination == :area_design do
        {:noreply, push_navigate(socket, to: "/setup/areas")}
      else
        {:noreply, socket}
      end
    else
      {:noreply, socket}
    end
  end

  def handle_async({:refresh_ha_inventory, bridge_id}, {:ok, {:error, reason}}, socket) do
    if MapSet.member?(socket.assigns.inventory_refreshing_ids, bridge_id) do
      {:noreply,
       socket
       |> finish_inventory_refresh(bridge_id)
       |> put_notice(:error, "Home Assistant inventory failed: #{operation_error(reason)}")}
    else
      {:noreply, socket}
    end
  end

  def handle_async({:refresh_ha_inventory, bridge_id}, {:exit, reason}, socket) do
    if MapSet.member?(socket.assigns.inventory_refreshing_ids, bridge_id) do
      {:noreply,
       socket
       |> finish_inventory_refresh(bridge_id)
       |> put_notice(:error, "Home Assistant inventory failed: #{operation_error(reason)}")}
    else
      {:noreply, socket}
    end
  end

  defp load_setup(socket) do
    status = Onboarding.status()
    bridges = Bridges.list_bridges() |> Enum.sort_by(&{&1.type, &1.name})
    ha_entries = bridges |> Enum.filter(&(&1.type == :ha)) |> Enum.map(&ha_entry/1)
    native_bridges = Enum.reject(bridges, &(&1.type == :ha))

    assign(socket,
      status: status,
      path_choice_open?: Map.get(socket.assigns, :path_choice_open?, false),
      inventory_refreshing_ids: Map.get(socket.assigns, :inventory_refreshing_ids, MapSet.new()),
      inventory_refresh_destinations:
        Map.get(socket.assigns, :inventory_refresh_destinations, %{}),
      bridges: bridges,
      ha_entries: ha_entries,
      native_bridges: native_bridges,
      steps: setup_steps(status, ha_entries, native_bridges)
    )
  end

  defp ha_entry(bridge) do
    case Inventory.latest(bridge) do
      {:ok, inventory} ->
        %{bridge: bridge, inventory: inventory, design: AreaDesign.design(bridge)}

      {:error, :inventory_not_fetched} ->
        %{bridge: bridge, inventory: nil, design: nil}
    end
  end

  defp setup_steps(status, ha_entries, native_bridges) do
    after_foundation = [
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
          "Sync Home Assistant inventory",
          inventory_fetched?(ha_entries),
          "/setup"
        ),
        step(
          "area-design",
          "Design HueWorks Areas",
          area_designs_complete?(ha_entries),
          "/setup/areas"
        ),
        step(
          "location",
          "Set location",
          status.location_configured?,
          "/config/general?return_to=setup"
        )
        | after_foundation
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
      [
        step(
          "location",
          "Set location",
          status.location_configured?,
          "/config/general?return_to=setup"
        ),
        step("areas", "Create Areas", status.area_count > 0, "/areas")
        | after_foundation
      ]
    end
  end

  defp step(id, title, complete?, href, opts \\ []) do
    %{id: id, title: title, complete?: complete?, href: href, optional?: opts[:optional] == true}
  end

  defp native_imported?([]), do: false
  defp native_imported?(bridges), do: Enum.all?(bridges, &Bridges.imported?/1)

  defp inventory_fetched?(entries),
    do: entries != [] and Enum.all?(entries, &(not is_nil(&1.inventory)))

  defp area_designs_complete?(entries),
    do: entries != [] and Enum.all?(entries, &area_design_complete?/1)

  defp ha_entities_imported?([]), do: false
  defp ha_entities_imported?(entries), do: Enum.all?(entries, &Bridges.imported?(&1.bridge))

  defp placement_reviewed?(status) do
    status.light_count + status.group_count > 0 and status.area_count > 0
  end

  defp parse_path("ha_assisted"), do: {:ok, :ha_assisted}
  defp parse_path("direct"), do: {:ok, :direct}
  defp parse_path(_path), do: {:error, :invalid_path}

  defp maybe_continue_ha_inventory(socket, %{"refresh_ha_inventory" => bridge_id}) do
    with bridge_id when is_integer(bridge_id) <- Util.parse_id(bridge_id),
         %Bridge{type: :ha} = bridge <- Bridges.get_bridge(bridge_id) do
      start_inventory_refresh(socket, bridge, :area_design)
    else
      _ -> put_notice(socket, :error, "Home Assistant bridge not found.")
    end
  end

  defp maybe_continue_ha_inventory(socket, _params), do: socket

  defp start_inventory_refresh(socket, bridge, destination) do
    socket
    |> update(:inventory_refreshing_ids, &MapSet.put(&1, bridge.id))
    |> update(
      :inventory_refresh_destinations,
      &Map.put(&1, bridge.id, destination)
    )
    |> start_async({:refresh_ha_inventory, bridge.id}, fn ->
      pipeline_module().create_import(bridge)
    end)
  end

  defp finish_inventory_refresh(socket, bridge_id) do
    socket
    |> update(:inventory_refreshing_ids, &MapSet.delete(&1, bridge_id))
    |> update(:inventory_refresh_destinations, &Map.delete(&1, bridge_id))
  end

  defp operation_error(%Ecto.Changeset{}), do: "the requested values were not valid"
  defp operation_error(reason) when is_binary(reason), do: reason

  defp operation_error(reason) when is_atom(reason),
    do: reason |> Atom.to_string() |> String.replace("_", " ")

  defp operation_error(_reason), do: "unexpected error"

  defp pipeline_module,
    do: Application.get_env(:hueworks, :onboarding_import_pipeline, Hueworks.Import.Pipeline)

  def source_label(:hue), do: "Hue"
  def source_label(:caseta), do: "Caseta"
  def source_label(:z2m), do: "Zigbee2MQTT"
  def source_label(source), do: to_string(source)

  def area_design_complete?(%{design: %{progress: %{resolved: resolved, total: total}}}),
    do: resolved == total

  def area_design_complete?(_entry), do: false

  def area_design_status(entries) do
    progress =
      Enum.reduce(entries, %{resolved: 0, total: 0}, fn
        %{design: %{progress: item}}, acc ->
          %{resolved: acc.resolved + item.resolved, total: acc.total + item.total}

        _entry, acc ->
          acc
      end)

    cond do
      progress.total == 0 -> "No spaces found"
      progress.resolved == progress.total -> "Ready"
      true -> "#{progress.total - progress.resolved} remain"
    end
  end

  def native_source_path(source) do
    params =
      %{"type" => to_string(source.kind)}
      |> maybe_put_query("host", source.host)
      |> maybe_put_query("external_id", source.external_id)

    "/config/bridges/new?" <> URI.encode_query(params)
  end

  defp maybe_put_query(params, _key, nil), do: params
  defp maybe_put_query(params, _key, ""), do: params
  defp maybe_put_query(params, key, value), do: Map.put(params, key, value)
end
