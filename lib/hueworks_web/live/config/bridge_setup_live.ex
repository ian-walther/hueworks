defmodule HueworksWeb.BridgeSetupLive do
  use Phoenix.LiveView

  alias Hueworks.Repo
  alias Hueworks.Schemas.Bridge
  alias Hueworks.Schemas.Room
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
       rooms: rooms
     )}
  end

  def handle_event("toggle_light", %{"id" => source_id}, socket) do
    {:noreply, update_plan(socket, :lights, source_id)}
  end

  def handle_event("toggle_group", %{"id" => source_id}, socket) do
    {:noreply, update_plan(socket, :groups, source_id)}
  end

  def handle_event("set_room_action", %{"room_id" => source_id, "action" => action}, socket) do
    plan = put_room_plan(socket.assigns.plan, source_id, %{"action" => action})
    {:noreply, assign(socket, plan: plan)}
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

  defp normalized_entries(normalized, key) do
    Normalize.fetch(normalized, key) || []
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
