defmodule HueworksWeb.BridgeReimportLive do
  use Phoenix.LiveView

  import Ecto.Query, only: [from: 2]
  import HueworksWeb.Notices

  alias Hueworks.Bridges
  alias Hueworks.Import

  alias Hueworks.Import.{
    DestructiveReview,
    Normalize,
    NormalizeFromDb,
    ReimportPlan,
    ReimportReview,
    ReviewPlan
  }

  alias Hueworks.Repo
  alias Hueworks.Schemas.{Bridge, Group, Light, Room}

  def mount(%{"id" => id}, _session, socket) do
    bridge = Repo.get!(Bridge, id)

    if Bridges.imported?(bridge) do
      if connected?(socket), do: send(self(), :import_configuration)

      {:ok,
       assign(socket,
         bridge: bridge,
         bridge_import: nil,
         import_status: :loading,
         import_error: nil,
         normalized_import: nil,
         normalized_db: nil,
         reimport: nil,
         plan: nil,
         review: nil,
         destructive_preview: [],
         destructive_confirmation: [],
         rooms: Repo.all(from(r in Room, order_by: [asc: r.name]))
       )}
    else
      {:ok, redirect(socket, to: "/config/bridges/#{bridge.id}/import")}
    end
  end

  def handle_event(
        "set_entity_resolution",
        %{"type" => type, "source_id" => source_id, "resolution" => resolution},
        socket
      ) do
    plan =
      socket.assigns.plan
      |> ReviewPlan.put_entity_resolution(type, source_id, resolution)
      |> sync_created_rooms(socket.assigns.reimport.plan, socket.assigns.normalized_import)

    {:noreply, assign_review(socket, plan)}
  end

  def handle_event(
        "set_entity_room",
        %{"type" => type, "source_id" => source_id, "target_room_id" => target_room_id},
        socket
      ) do
    plan =
      socket.assigns.plan
      |> put_entity_destination(type, source_id, target_room_id)
      |> sync_created_rooms(socket.assigns.reimport.plan, socket.assigns.normalized_import)

    {:noreply, assign_review(socket, plan)}
  end

  def handle_event(
        "bulk_resolution",
        %{"status" => status, "resolution" => resolution},
        socket
      ) do
    plan =
      ReviewPlan.apply_bulk_resolution(
        socket.assigns.plan,
        socket.assigns.reimport.statuses,
        status,
        resolution
      )
      |> sync_created_rooms(socket.assigns.reimport.plan, socket.assigns.normalized_import)

    {:noreply, assign_review(socket, plan)}
  end

  def handle_event("import_configuration", _params, socket) do
    {:noreply, start_import(socket)}
  end

  def handle_event("apply_reimport", params, socket) do
    confirmed? = Map.get(params, "confirmed") == "true"

    case destructive_confirmation(socket, confirmed?) do
      {:confirm, confirmation} ->
        {:noreply, assign(socket, destructive_confirmation: confirmation)}

      :apply ->
        apply_reimport(socket)
    end
  end

  def handle_event("cancel_destructive_confirmation", _params, socket) do
    {:noreply, assign(socket, destructive_confirmation: [])}
  end

  def handle_info(:import_configuration, socket) do
    {:noreply, start_import(socket)}
  end

  def handle_info(_message, socket), do: {:noreply, socket}

  def resolution_options(:new),
    do: [{"Do Not Import", "do_not_import"}, {"Import", "import"}]

  def resolution_options(:duplicate) do
    [
      {"Import hidden duplicate", "import_hidden_duplicate"},
      {"Import as real entity", "import_real"},
      {"Do Not Import", "do_not_import"}
    ]
  end

  def resolution_options(:missing),
    do: [{"Keep", "keep"}, {"Disable", "disable"}, {"Delete", "delete"}]

  def resolution_options(:ambiguous_identity), do: [{"Keep separate", "keep_separate"}]
  def resolution_options(_status), do: []

  def status_label(:new), do: "New"
  def status_label(:duplicate), do: "Possible duplicate"
  def status_label(:ambiguous_identity), do: "Identity needs review"
  def status_label(:missing), do: "Removed upstream"
  def status_label(status), do: status |> to_string() |> String.replace("_", " ")

  def review_attention?(summary) do
    Enum.any?([:removed, :new, :automatic_updates, :membership_warnings], fn key ->
      Map.get(summary, key, 0) > 0
    end)
  end

  def format_review_value(nil), do: "Not reported"
  def format_review_value(true), do: "Yes"
  def format_review_value(false), do: "No"
  def format_review_value(value) when is_binary(value), do: value
  def format_review_value(value) when is_number(value), do: to_string(value)
  def format_review_value(value) when is_atom(value), do: to_string(value)

  def format_review_value(value) when is_list(value) do
    case value do
      [] -> "None"
      values -> Enum.map_join(values, ", ", &format_review_value/1)
    end
  end

  def format_review_value(value) when is_map(value) do
    value
    |> Jason.encode!()
    |> truncate(140)
  end

  def format_review_value(value), do: inspect(value)

  def destructive_preview(items, type, source_id) do
    Enum.find(items, fn item -> item.type == type and item.source_id == source_id end)
  end

  def create_room_value(reimport_plan, incoming) when is_map(incoming) do
    room_source_id =
      incoming
      |> Normalize.fetch(:room_source_id)
      |> Normalize.normalize_source_id()

    if is_binary(room_source_id) and
         ReviewPlan.room_action(reimport_plan, room_source_id) == "skip" do
      "bridge_room:#{room_source_id}"
    end
  end

  def create_room_value(_reimport_plan, _incoming), do: nil

  defp start_import(socket) do
    case pipeline_module().create_import(socket.assigns.bridge) do
      {:ok, bridge_import} ->
        normalized_import = bridge_import.normalized_blob
        normalized_db = NormalizeFromDb.normalize(socket.assigns.bridge)

        reimport =
          ReimportPlan.build(normalized_import, normalized_db, socket.assigns.rooms)

        socket
        |> assign(
          bridge_import: bridge_import,
          import_status: :ready,
          import_error: nil,
          normalized_import: normalized_import,
          normalized_db: normalized_db,
          reimport: reimport
        )
        |> assign_review(reimport.plan)

      {:error, message} ->
        socket
        |> assign(import_status: :error, import_error: message)
        |> put_notice(:error, message)
    end
  end

  defp assign_review(socket, plan) do
    review =
      ReimportReview.build(
        socket.assigns.bridge,
        socket.assigns.normalized_import,
        socket.assigns.reimport,
        plan,
        current_lights(socket.assigns.bridge.id),
        current_groups(socket.assigns.bridge.id),
        socket.assigns.rooms
      )

    assign(socket,
      plan: plan,
      review: review,
      destructive_preview: DestructiveReview.summarize(socket.assigns.bridge, plan),
      destructive_confirmation: []
    )
  end

  defp put_entity_destination(plan, type, source_id, "bridge_room:" <> _room_source_id),
    do: ReviewPlan.put_entity_room(plan, type, source_id, "bridge_room")

  defp put_entity_destination(plan, type, source_id, target_room_id) do
    ReviewPlan.put_entity_room(plan, type, source_id, target_room_id)
  end

  defp sync_created_rooms(plan, base_plan, normalized_import) do
    base_plan
    |> Normalize.fetch(:rooms)
    |> Kernel.||(%{})
    |> Enum.reduce(plan, fn {room_source_id, room_plan}, acc ->
      if Normalize.fetch(room_plan, :action) == "skip" do
        action =
          if bridge_room_targeted?(acc, normalized_import, room_source_id),
            do: "create",
            else: "skip"

        ReviewPlan.put_room(acc, room_source_id, %{
          "action" => action,
          "target_room_id" => nil
        })
      else
        acc
      end
    end)
  end

  defp bridge_room_targeted?(plan, normalized_import, room_source_id) do
    Enum.any?([:lights, :groups], fn type ->
      normalized_import
      |> Normalize.fetch(type)
      |> Kernel.||([])
      |> Enum.any?(fn entity ->
        source_id = entity |> Normalize.fetch(:source_id) |> Normalize.normalize_source_id()

        entity_room_source_id =
          entity
          |> Normalize.fetch(:room_source_id)
          |> Normalize.normalize_source_id()

        entity_room_source_id == room_source_id and
          ReviewPlan.selected?(plan, type, source_id) and
          ReviewPlan.entity_target_room(plan, type, source_id) == "bridge_room"
      end)
    end)
  end

  defp apply_reimport(socket) do
    case Import.apply_review(
           socket.assigns.bridge,
           socket.assigns.bridge_import,
           socket.assigns.normalized_import,
           socket.assigns.plan
         ) do
      {:ok, %{bridge: bridge}} ->
        transaction = socket.assigns.review.transaction

        message =
          "Bridge changes applied: #{transaction.import} imported, #{transaction.disable} disabled, #{transaction.delete} deleted, #{transaction.automatic_updates} automatically refreshed."

        {:noreply,
         socket
         |> assign(bridge: bridge, destructive_confirmation: [])
         |> put_notice(:info, message)
         |> push_navigate(to: "/config/bridges")}

      {:error, reason} ->
        {:noreply, handle_apply_error(socket, reason)}
    end
  end

  defp destructive_confirmation(socket, false) do
    case DestructiveReview.summarize(socket.assigns.bridge, socket.assigns.plan) do
      [] -> :apply
      confirmation -> {:confirm, confirmation}
    end
  end

  defp destructive_confirmation(_socket, true), do: :apply

  defp handle_apply_error(socket, reason) do
    message = apply_error_message(reason)

    socket
    |> maybe_refresh_stale_review(reason)
    |> assign(import_status: :error, import_error: message)
    |> put_notice(:error, message)
  end

  defp maybe_refresh_stale_review(socket, reason) do
    if stale_review_reason?(reason) do
      normalized_db = NormalizeFromDb.normalize(socket.assigns.bridge)

      reimport =
        ReimportPlan.build(socket.assigns.normalized_import, normalized_db, socket.assigns.rooms)

      socket
      |> assign(normalized_db: normalized_db, reimport: reimport)
      |> assign_review(reimport.plan)
    else
      socket
    end
  end

  defp stale_review_reason?({:duplicate_classification_changed, _type, _source_id}), do: true
  defp stale_review_reason?({:invalid_duplicate, _type, _source_id}), do: true
  defp stale_review_reason?({:stale_resolution, _type, _source_id}), do: true
  defp stale_review_reason?(_reason), do: false

  defp apply_error_message({:duplicate_classification_changed, type, source_id}) do
    "Duplicate classification changed for #{entity_reference(type, source_id)}. The review was refreshed; check the choices again."
  end

  defp apply_error_message({:invalid_duplicate, type, source_id}) do
    "The duplicate choice for #{entity_reference(type, source_id)} is no longer valid. The review was refreshed."
  end

  defp apply_error_message({:stale_resolution, type, source_id}) do
    "The review is out of date for #{entity_reference(type, source_id)}. It was refreshed; check the choices again."
  end

  defp apply_error_message(reason), do: inspect(reason)

  defp entity_reference(type, source_id), do: "#{type} #{source_id}"

  defp current_lights(bridge_id) do
    Repo.all(
      from(l in Light,
        where: l.bridge_id == ^bridge_id,
        preload: [:room]
      )
    )
  end

  defp current_groups(bridge_id) do
    Repo.all(
      from(g in Group,
        where: g.bridge_id == ^bridge_id,
        preload: [:room, :lights]
      )
    )
  end

  defp pipeline_module do
    Application.get_env(:hueworks, :import_pipeline, Hueworks.Import.Pipeline)
  end

  defp truncate(value, max) when byte_size(value) <= max, do: value
  defp truncate(value, max), do: binary_part(value, 0, max) <> "..."
end
