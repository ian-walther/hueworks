defmodule HueworksWeb.BridgeSetupLive do
  use Phoenix.LiveView

  alias Hueworks.Repo
  alias Hueworks.Schemas.Bridge
  alias Hueworks.Schemas.Room
  alias Hueworks.Bridges
  alias Hueworks.Import.{Materialize, Plan, Normalize, Link}
  import Hueworks.Import.Normalize, only: [fetch: 2]

  def mount(%{"id" => id}, _session, socket) do
    bridge = Repo.get!(Bridge, id)
    rooms = Repo.all(Room)

    if connected?(socket) do
      send(self(), :import_configuration)
    end

    {:ok,
     assign(socket,
       bridge: bridge,
       bridge_import: nil,
       import_status: :idle,
       import_error: nil,
       import_blob: nil,
       normalized: nil,
       plan: nil,
       reimport: false,
       rooms: rooms
     )}
  end

  def handle_event("toggle_light", %{"id" => source_id}, socket) do
    {:noreply, update_plan(socket, :lights, source_id)}
  end

  def handle_event("toggle_group", %{"id" => source_id}, socket) do
    {:noreply, update_plan(socket, :groups, source_id)}
  end

  def handle_event("toggle_all", %{"action" => action}, socket) do
    {:noreply, apply_bulk_toggle(socket, action)}
  end

  def handle_event("toggle_room", %{"room_id" => room_id, "action" => action}, socket) do
    {:noreply, apply_room_toggle(socket, room_id, action)}
  end

  def handle_event(
        "toggle_room_section",
        %{"room_id" => room_id, "section" => section, "action" => action},
        socket
      ) do
    {:noreply, apply_room_section_toggle(socket, room_id, section, action)}
  end

  def handle_event("set_room_action", %{"room_id" => source_id, "action" => action}, socket) do
    plan = put_room_plan(socket.assigns.plan, source_id, %{"action" => action})
    {:noreply, assign(socket, plan: plan)}
  end

  def handle_event("toggle_reimport", %{"enabled" => enabled}, socket) do
    {:noreply, assign(socket, reimport: enabled == "true")}
  end

  def handle_event("import_configuration", _params, socket) do
    {:noreply, start_import(socket)}
  end

  def handle_event(
        "set_room_merge",
        %{"room_id" => source_id, "target_room_id" => target_room_id},
        socket
      ) do
    plan =
      put_room_plan(socket.assigns.plan, source_id, %{
        "action" => "merge",
        "target_room_id" => target_room_id
      })

    {:noreply, assign(socket, plan: plan)}
  end

  def handle_event("apply_materialization", _params, socket) do
    plan = socket.assigns.plan || %{}
    normalized = socket.assigns.normalized || %{}
    bridge_import = socket.assigns.bridge_import

    with {:ok, reviewed} <- update_review_blob(bridge_import, plan),
         :ok <- maybe_delete_entities(socket),
         :ok <- Materialize.materialize(socket.assigns.bridge, normalized, plan),
         :ok <- Link.apply(),
         {:ok, applied} <- mark_applied(reviewed),
         {:ok, bridge} <- mark_bridge_complete(socket.assigns.bridge) do
      {:noreply,
       socket
       |> assign(bridge_import: applied, import_status: :applied, bridge: bridge)
       |> push_navigate(to: "/config")}
    else
      {:error, reason} ->
        {:noreply, assign(socket, import_status: :error, import_error: inspect(reason))}
    end
  end

  def handle_info(:import_configuration, socket) do
    {:noreply, start_import(socket)}
  end

  defp start_import(socket) do
    case pipeline_module().create_import(socket.assigns.bridge) do
      {:ok, bridge_import} ->
        normalized = bridge_import.normalized_blob
        plan = bridge_import.review_blob || Plan.build_default(normalized)

        assign(socket,
          import_status: :ok,
          import_error: nil,
          import_blob: bridge_import.raw_blob,
          bridge_import: bridge_import,
          normalized: normalized,
          plan: plan
        )

      {:error, message} ->
        assign(socket, import_status: :error, import_error: message)
    end
  end

  defp update_plan(socket, type, source_id) do
    source_id = Normalize.normalize_source_id(source_id)
    plan = socket.assigns.plan || %{}
    map = Normalize.fetch(plan, type) || %{}

    if is_binary(source_id) do
      current = Map.get(map, source_id, true)
      updated = Map.put(map, source_id, !current)
      assign(socket, plan: Map.put(plan, type, updated))
    else
      assign(socket, plan: plan)
    end
  end

  defp put_room_plan(plan, source_id, attrs) do
    source_id = Normalize.normalize_source_id(source_id)
    plan = plan || %{}
    rooms = Normalize.fetch(plan, :rooms) || %{}

    if is_binary(source_id) do
      current = Map.get(rooms, source_id, %{})
      updated = Map.merge(current, attrs)
      Map.put(plan, :rooms, Map.put(rooms, source_id, updated))
    else
      plan
    end
  end

  defp update_review_blob(nil, _plan), do: {:ok, nil}

  defp update_review_blob(bridge_import, plan) do
    bridge_import
    |> Hueworks.Schemas.BridgeImport.changeset(%{review_blob: plan, status: :reviewed})
    |> Repo.update()
  end

  defp mark_applied(bridge_import) do
    bridge_import
    |> Hueworks.Schemas.BridgeImport.changeset(%{status: :applied})
    |> Repo.update()
  end

  defp mark_bridge_complete(bridge) do
    bridge
    |> Bridge.changeset(%{import_complete: true})
    |> Repo.update()
  end

  defp maybe_delete_entities(%{assigns: %{reimport: true, bridge: bridge}}) do
    case Bridges.delete_entities(bridge) do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp maybe_delete_entities(_socket), do: :ok

  defp normalized_entries(normalized, key) do
    Normalize.fetch(normalized, key) || []
  end

  defp apply_bulk_toggle(socket, value) do
    plan = socket.assigns.plan || %{}
    normalized = socket.assigns.normalized || %{}
    rooms = normalized_entries(normalized, :rooms)
    lights = normalized_entries(normalized, :lights)
    groups = normalized_entries(normalized, :groups)
    room_ids = entity_ids(rooms)
    light_ids = entity_ids(lights)
    group_ids = entity_ids(groups)

    action = if value == "check", do: "create", else: "skip"
    selected = value == "check"

    plan
    |> put_room_actions(room_ids, action)
    |> put_selection(:lights, light_ids, selected)
    |> put_selection(:groups, group_ids, selected)
    |> then(&assign(socket, plan: &1))
  end

  defp apply_room_toggle(socket, room_id, value) do
    plan = socket.assigns.plan || %{}
    normalized = socket.assigns.normalized || %{}
    selected = value == "check"
    action = if selected, do: "create", else: "skip"

    light_ids = room_entity_ids(normalized, room_id, :lights)
    group_ids = room_entity_ids(normalized, room_id, :groups)
    room_ids = room_entity_ids(normalized, room_id, :rooms)

    plan
    |> put_room_actions(room_ids, action)
    |> put_selection(:lights, light_ids, selected)
    |> put_selection(:groups, group_ids, selected)
    |> then(&assign(socket, plan: &1))
  end

  defp apply_room_section_toggle(socket, room_id, section, value) do
    plan = socket.assigns.plan || %{}
    normalized = socket.assigns.normalized || %{}
    selected = value == "check"
    section_key = if section == "groups", do: :groups, else: :lights

    ids =
      if room_id == "unassigned" do
        unassigned_entity_ids(normalized, section_key)
      else
        room_entity_ids(normalized, room_id, section_key)
      end

    plan
    |> put_selection(section_key, ids, selected)
    |> then(&assign(socket, plan: &1))
  end

  defp put_room_actions(plan, room_ids, action) do
    plan = plan || %{}
    rooms = Normalize.fetch(plan, :rooms) || %{}

    updated =
      Enum.reduce(room_ids, rooms, fn room_id, acc ->
        current = Map.get(acc, room_id, %{})
        Map.put(acc, room_id, Map.put(current, "action", action))
      end)

    Map.put(plan, :rooms, updated)
  end

  defp put_selection(plan, key, ids, selected) do
    plan = plan || %{}
    map = Normalize.fetch(plan, key) || %{}

    updated =
      Enum.reduce(ids, map, fn id, acc ->
        Map.put(acc, id, selected)
      end)

    Map.put(plan, key, updated)
  end

  defp entity_ids(entries) do
    entries
    |> Enum.map(fn entry ->
      entry
      |> Normalize.fetch(:source_id)
      |> Normalize.normalize_source_id()
    end)
    |> Enum.filter(&is_binary/1)
  end

  defp room_entity_ids(_normalized, room_id, :rooms) do
    case Normalize.normalize_source_id(room_id) do
      nil -> []
      id -> [id]
    end
  end

  defp room_entity_ids(normalized, room_id, type) when type in [:lights, :groups] do
    room_key = Normalize.normalize_source_id(room_id)
    entries = normalized_entries(normalized, type)

    if is_binary(room_key) do
      entries
      |> Enum.reduce([], fn entry, acc ->
        entry_room =
          entry
          |> Normalize.fetch(:room_source_id)
          |> Normalize.normalize_source_id()

        if entry_room == room_key do
          case Normalize.normalize_source_id(Normalize.fetch(entry, :source_id)) do
            nil -> acc
            id -> [id | acc]
          end
        else
          acc
        end
      end)
      |> Enum.reverse()
    else
      []
    end
  end

  defp unassigned_entity_ids(normalized, type) when type in [:lights, :groups] do
    room_keys =
      normalized_entries(normalized, :rooms)
      |> Enum.map(fn room ->
        room
        |> Normalize.fetch(:source_id)
        |> Normalize.normalize_source_id()
      end)
      |> Enum.filter(&is_binary/1)

    normalized_entries(normalized, type)
    |> Enum.reduce([], fn entry, acc ->
      room_key =
        entry
        |> Normalize.fetch(:room_source_id)
        |> Normalize.normalize_source_id()

      if not is_binary(room_key) or not Enum.member?(room_keys, room_key) do
        case Normalize.normalize_source_id(Normalize.fetch(entry, :source_id)) do
          nil -> acc
          id -> [id | acc]
        end
      else
        acc
      end
    end)
    |> Enum.reverse()
  end

  defp pipeline_module do
    Application.get_env(:hueworks, :import_pipeline, Hueworks.Import.Pipeline)
  end

  defp plan_selected?(plan, key, source_id) do
    source_id = Normalize.normalize_source_id(source_id)
    map = Normalize.fetch(plan, key) || %{}

    if is_binary(source_id) do
      case Map.get(map, source_id, true) do
        false -> false
        _ -> true
      end
    else
      false
    end
  end

  defp room_action(plan, source_id) do
    source_id = Normalize.normalize_source_id(source_id)
    rooms = Normalize.fetch(plan, :rooms) || %{}

    case source_id do
      nil ->
        "create"

      _ ->
        Map.get(rooms, source_id, %{})
        |> Normalize.fetch(:action)
        |> case do
          nil -> "create"
          value -> value
        end
    end
  end

  defp room_merge_target(plan, source_id) do
    source_id = Normalize.normalize_source_id(source_id)
    rooms = Normalize.fetch(plan, :rooms) || %{}

    case source_id do
      nil ->
        nil

      _ ->
        Map.get(rooms, source_id, %{})
        |> Normalize.fetch(:target_room_id)
    end
  end
end
