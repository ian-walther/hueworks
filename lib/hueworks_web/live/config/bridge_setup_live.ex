defmodule HueworksWeb.BridgeSetupLive do
  use Phoenix.LiveView

  import HueworksWeb.Notices

  alias Hueworks.Repo
  alias Hueworks.Bridges
  alias Hueworks.Import

  alias Hueworks.Import.{
    DestructiveReview,
    Normalize,
    NormalizeFromDb,
    Plan,
    ReimportPlan,
    ReviewPlan
  }

  alias Hueworks.Schemas.Room
  alias Hueworks.Schemas.Bridge
  import Hueworks.Import.Normalize, only: [fetch: 2]

  def mount(%{"id" => id} = params, _session, socket) do
    bridge = Repo.get!(Bridge, id)
    rooms = Repo.all(Room)
    reimport = Map.get(params, "reimport") == "1"

    if not reimport and Bridges.imported?(bridge) do
      {:ok, redirect(socket, to: "/config/bridge/#{bridge.id}/setup?reimport=1")}
    else
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
         normalized_display: nil,
         normalized_import: nil,
         normalized_db: nil,
         plan: nil,
         reimport: reimport,
         reimport_statuses: %{},
         reimport_summary: %{},
         destructive_confirmation: [],
         rooms: rooms
       )}
    end
  end

  def handle_event("toggle_light", %{"id" => source_id}, socket) do
    plan = ReviewPlan.toggle_entity(socket.assigns.plan, :lights, source_id)
    {:noreply, assign_plan(socket, plan)}
  end

  def handle_event("toggle_group", %{"id" => source_id}, socket) do
    plan = ReviewPlan.toggle_entity(socket.assigns.plan, :groups, source_id)
    {:noreply, assign_plan(socket, plan)}
  end

  def handle_event("toggle_all", %{"action" => action}, socket) do
    {:noreply, apply_bulk_toggle(socket, action)}
  end

  def handle_event(
        "bulk_resolution",
        %{"status" => status, "resolution" => resolution},
        socket
      ) do
    {:noreply, apply_bulk_resolution(socket, status, resolution)}
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
    plan = ReviewPlan.put_room(socket.assigns.plan, source_id, %{"action" => action})
    {:noreply, assign_plan(socket, plan)}
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
      ReviewPlan.put_room(socket.assigns.plan, source_id, %{
        "action" => "merge",
        "target_room_id" => target_room_id
      })

    {:noreply, assign_plan(socket, plan)}
  end

  def handle_event(
        "set_entity_room",
        %{"type" => type, "source_id" => source_id, "target_room_id" => target_room_id},
        socket
      ) do
    plan = ReviewPlan.put_entity_room(socket.assigns.plan, type, source_id, target_room_id)
    {:noreply, assign_plan(socket, plan)}
  end

  def handle_event(
        "set_entity_resolution",
        %{"type" => type, "source_id" => source_id, "resolution" => resolution},
        socket
      ) do
    plan = ReviewPlan.put_entity_resolution(socket.assigns.plan, type, source_id, resolution)
    {:noreply, assign_plan(socket, plan)}
  end

  def handle_event("apply_materialization", params, socket) do
    plan = socket.assigns.plan || %{}
    normalized = socket.assigns.normalized_import || %{}
    bridge_import = socket.assigns.bridge_import
    confirmed? = Map.get(params, "confirmed") == "true"

    case destructive_confirmation(socket, plan, confirmed?) do
      {:confirm, confirmation} ->
        {:noreply,
         socket
         |> assign(destructive_confirmation: confirmation)
         |> put_notice(:info, "Review and confirm destructive reimport changes before applying.")}

      :apply ->
        with {:ok, %{bridge_import: applied, bridge: bridge}} <-
               Import.apply_review(socket.assigns.bridge, bridge_import, normalized, plan) do
          {:noreply,
           socket
           |> assign(
             bridge_import: applied,
             import_status: :applied,
             bridge: bridge,
             destructive_confirmation: []
           )
           |> push_navigate(to: "/config")}
        else
          {:error, reason} ->
            {:noreply, handle_apply_error(socket, reason)}
        end
    end
  end

  def handle_event("cancel_destructive_confirmation", _params, socket) do
    {:noreply, assign(socket, destructive_confirmation: [])}
  end

  def handle_info(:import_configuration, socket) do
    {:noreply, start_import(socket)}
  end

  def handle_info(_message, socket) do
    {:noreply, socket}
  end

  defp start_import(socket) do
    case pipeline_module().create_import(socket.assigns.bridge) do
      {:ok, bridge_import} ->
        normalized = bridge_import.normalized_blob

        socket =
          assign(socket,
            import_status: :ok,
            import_error: nil,
            import_blob: bridge_import.raw_blob,
            bridge_import: bridge_import,
            normalized_import: normalized
          )
          |> put_notice(:info, import_flash_info(bridge_import))

        socket
        |> refresh_reimport_plan()
        |> assign_default_plan_if_needed(bridge_import)

      {:error, message} ->
        socket
        |> assign(import_status: :error, import_error: message)
        |> put_notice(:error, message)
    end
  end

  defp refresh_reimport_plan(socket) do
    if socket.assigns.reimport and socket.assigns.normalized_import do
      normalized_db = NormalizeFromDb.normalize(socket.assigns.bridge)

      reimport =
        ReimportPlan.build(socket.assigns.normalized_import, normalized_db, socket.assigns.rooms)

      assign(socket,
        normalized: reimport.normalized,
        normalized_display: reimport.normalized,
        normalized_db: normalized_db,
        plan: reimport.plan,
        reimport_statuses: reimport.statuses,
        reimport_summary: reimport_summary(reimport.statuses)
      )
    else
      socket
    end
  end

  defp assign_default_plan_if_needed(socket, bridge_import) do
    if socket.assigns.reimport do
      socket
    else
      normalized = socket.assigns.normalized_import || %{}

      review_blob =
        case bridge_import do
          nil -> nil
          _ -> bridge_import.review_blob
        end

      plan =
        review_blob
        |> Kernel.||(Plan.build_default(normalized))
        |> ReviewPlan.apply_room_merge_defaults(normalized, socket.assigns.rooms)

      assign(socket,
        normalized: normalized,
        normalized_display: normalized,
        normalized_db: nil,
        plan: plan,
        reimport_statuses: %{}
      )
    end
  end

  defp assign_plan(socket, plan), do: assign(socket, plan: plan, destructive_confirmation: [])

  defp destructive_confirmation(_socket, _plan, true), do: :apply

  defp destructive_confirmation(%{assigns: %{reimport: false}}, _plan, _confirmed?), do: :apply

  defp destructive_confirmation(socket, plan, _confirmed?) do
    case DestructiveReview.summarize(socket.assigns.bridge, plan) do
      [] -> :apply
      confirmation -> {:confirm, confirmation}
    end
  end

  defp handle_apply_error(socket, reason) do
    message = apply_error_message(reason)

    socket
    |> maybe_refresh_reimport_review(reason)
    |> assign(import_status: :error, import_error: message)
    |> put_notice(:error, message)
  end

  defp maybe_refresh_reimport_review(socket, reason) do
    if stale_review_reason?(reason) do
      refresh_reimport_plan(socket)
    else
      socket
    end
  end

  defp stale_review_reason?({:duplicate_classification_changed, _type, _source_id}), do: true
  defp stale_review_reason?({:invalid_duplicate, _type, _source_id}), do: true
  defp stale_review_reason?({:stale_resolution, _type, _source_id}), do: true
  defp stale_review_reason?(_reason), do: false

  defp apply_error_message({:duplicate_classification_changed, type, source_id}) do
    "This reimport review is out of date for #{entity_reference(type, source_id)} because duplicate classification changed. The review has been refreshed; please re-check your selections."
  end

  defp apply_error_message({:invalid_duplicate, type, source_id}) do
    "The duplicate resolution for #{entity_reference(type, source_id)} is no longer valid. The review has been refreshed; please re-check your selections."
  end

  defp apply_error_message({:stale_resolution, type, source_id}) do
    "This reimport review is out of date for #{entity_reference(type, source_id)}. The review has been refreshed; please re-check your selections."
  end

  defp apply_error_message(reason), do: inspect(reason)

  defp entity_reference(type, source_id) do
    "#{Atom.to_string(type)} #{source_id}"
  end

  defp normalized_entries(normalized, key) do
    Normalize.fetch(normalized, key) || []
  end

  defp normalized_for_plan(socket) do
    if socket.assigns.reimport do
      socket.assigns.normalized_import || %{}
    else
      socket.assigns.normalized || %{}
    end
  end

  defp reimport_status(statuses, key, source_id) do
    source_id = Normalize.normalize_source_id(source_id)
    map = Normalize.fetch(statuses, key) || %{}
    Map.get(map, source_id)
  end

  defp reimport_disabled?(statuses, key, source_id) do
    reimport_status(statuses, key, source_id) in [:missing, :ambiguous_identity]
  end

  defp resolution_controls?(reimport, status),
    do: reimport and status in [:duplicate, :missing, :ambiguous_identity]

  defp resolution_options(:duplicate) do
    [
      {"Import hidden duplicate", "import_hidden_duplicate"},
      {"Import as real entity", "import_real"},
      {"Do not import", "do_not_import"}
    ]
  end

  defp resolution_options(:missing) do
    [
      {"Keep", "keep"},
      {"Disable", "disable"},
      {"Delete", "delete"}
    ]
  end

  defp resolution_options(:ambiguous_identity), do: [{"Keep separate", "keep_separate"}]
  defp resolution_options(_status), do: []

  defp reimport_summary(statuses) do
    statuses
    |> Enum.flat_map(fn
      {key, values} when key in [:lights, "lights", :groups, "groups"] and is_map(values) ->
        Map.values(values)

      _ ->
        []
    end)
    |> Enum.frequencies()
  end

  defp summary_count(summary, status), do: Map.get(summary || %{}, status, 0)

  defp apply_bulk_toggle(socket, value) do
    normalized = normalized_for_plan(socket)

    socket.assigns.plan
    |> ReviewPlan.apply_bulk_toggle(normalized, socket.assigns.rooms, value)
    |> then(&assign_plan(socket, &1))
  end

  defp apply_room_toggle(socket, room_id, value) do
    normalized = normalized_for_plan(socket)

    socket.assigns.plan
    |> ReviewPlan.apply_room_toggle(normalized, socket.assigns.rooms, room_id, value)
    |> then(&assign_plan(socket, &1))
  end

  defp apply_room_section_toggle(socket, room_id, section, value) do
    normalized = normalized_for_plan(socket)

    socket.assigns.plan
    |> ReviewPlan.apply_room_section_toggle(normalized, room_id, section, value)
    |> then(&assign_plan(socket, &1))
  end

  defp apply_bulk_resolution(socket, status, resolution) do
    statuses = socket.assigns.reimport_statuses || %{}

    socket.assigns.plan
    |> ReviewPlan.apply_bulk_resolution(statuses, status, resolution)
    |> then(&assign_plan(socket, &1))
  end

  defp pipeline_module do
    Application.get_env(:hueworks, :import_pipeline, Hueworks.Import.Pipeline)
  end

  defp plan_selected?(plan, key, source_id) do
    ReviewPlan.selected?(plan, key, source_id)
  end

  defp entity_target_room(plan, key, source_id) do
    ReviewPlan.entity_target_room(plan, key, source_id)
  end

  defp entity_resolution(plan, key, source_id) do
    ReviewPlan.entity_resolution(plan, key, source_id)
  end

  defp room_action(plan, source_id) do
    ReviewPlan.room_action(plan, source_id)
  end

  defp room_merge_target(plan, source_id) do
    ReviewPlan.room_merge_target(plan, source_id)
  end

  defp import_flash_info(%{status: status, imported_at: imported_at}) do
    "Configuration loaded into memory. Import status: #{status}. Imported at: #{imported_at}."
  end

  defp import_flash_info(_bridge_import), do: "Configuration loaded into memory."
end
