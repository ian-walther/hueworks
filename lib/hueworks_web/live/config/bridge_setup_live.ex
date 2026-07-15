defmodule HueworksWeb.BridgeSetupLive do
  use Phoenix.LiveView

  import Hueworks.Import.Normalize, only: [fetch: 2]
  import HueworksWeb.Notices

  alias Hueworks.Bridges
  alias Hueworks.Import
  alias Hueworks.Import.{Normalize, Plan, ReviewPlan}
  alias Hueworks.Repo
  alias Hueworks.Schemas.{Bridge, Room}

  def mount(%{"id" => id}, _session, socket) do
    bridge = Repo.get!(Bridge, id)

    if Bridges.imported?(bridge) do
      {:ok, redirect(socket, to: "/config/bridges/#{bridge.id}/reimport")}
    else
      if connected?(socket), do: send(self(), :import_configuration)

      {:ok,
       assign(socket,
         bridge: bridge,
         bridge_import: nil,
         import_status: :loading,
         import_error: nil,
         normalized: nil,
         plan: nil,
         rooms: Repo.all(Room)
       )}
    end
  end

  def handle_event("toggle_light", %{"id" => source_id}, socket) do
    {:noreply,
     update_plan(socket, ReviewPlan.toggle_entity(socket.assigns.plan, :lights, source_id))}
  end

  def handle_event("toggle_group", %{"id" => source_id}, socket) do
    {:noreply,
     update_plan(socket, ReviewPlan.toggle_entity(socket.assigns.plan, :groups, source_id))}
  end

  def handle_event("toggle_all", %{"action" => action}, socket) do
    plan =
      ReviewPlan.apply_bulk_toggle(
        socket.assigns.plan,
        socket.assigns.normalized,
        socket.assigns.rooms,
        action
      )

    {:noreply, update_plan(socket, plan)}
  end

  def handle_event("toggle_room", %{"room_id" => room_id, "action" => action}, socket) do
    plan =
      ReviewPlan.apply_room_toggle(
        socket.assigns.plan,
        socket.assigns.normalized,
        socket.assigns.rooms,
        room_id,
        action
      )

    {:noreply, update_plan(socket, plan)}
  end

  def handle_event(
        "toggle_room_section",
        %{"room_id" => room_id, "section" => section, "action" => action},
        socket
      ) do
    plan =
      ReviewPlan.apply_room_section_toggle(
        socket.assigns.plan,
        socket.assigns.normalized,
        room_id,
        section,
        action
      )

    {:noreply, update_plan(socket, plan)}
  end

  def handle_event("set_room_action", %{"room_id" => source_id, "action" => action}, socket) do
    {:noreply,
     update_plan(
       socket,
       ReviewPlan.put_room(socket.assigns.plan, source_id, %{"action" => action})
     )}
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

    {:noreply, update_plan(socket, plan)}
  end

  def handle_event(
        "set_entity_room",
        %{"type" => type, "source_id" => source_id, "target_room_id" => target_room_id},
        socket
      ) do
    plan = ReviewPlan.put_entity_room(socket.assigns.plan, type, source_id, target_room_id)
    {:noreply, update_plan(socket, plan)}
  end

  def handle_event("import_configuration", _params, socket) do
    {:noreply, start_import(socket)}
  end

  def handle_event("apply_materialization", _params, socket) do
    case Import.apply_review(
           socket.assigns.bridge,
           socket.assigns.bridge_import,
           socket.assigns.normalized,
           socket.assigns.plan || %{}
         ) do
      {:ok, %{bridge: bridge}} ->
        {:noreply,
         socket
         |> assign(bridge: bridge, import_status: :applied)
         |> put_notice(:info, "Bridge import applied successfully.")
         |> push_navigate(to: "/config/bridges")}

      {:error, reason} ->
        message = inspect(reason)

        {:noreply,
         socket
         |> assign(import_status: :error, import_error: message)
         |> put_notice(:error, message)}
    end
  end

  def handle_info(:import_configuration, socket), do: {:noreply, start_import(socket)}
  def handle_info(_message, socket), do: {:noreply, socket}

  attr(:title, :string, required: true)
  attr(:type, :atom, required: true)
  attr(:room_id, :any, required: true)
  attr(:entries, :list, required: true)
  attr(:plan, :map, required: true)

  def import_entity_section(assigns) do
    assigns =
      assign(
        assigns,
        :event,
        if(assigns.type == :lights, do: "toggle_light", else: "toggle_group")
      )

    ~H"""
    <section class="hw-import-entity-section">
      <header>
        <h3><%= @title %></h3>
        <div class="hw-row-actions">
          <button
            class="hw-button"
            type="button"
            phx-click="toggle_room_section"
            phx-value-room_id={@room_id}
            phx-value-section={@type}
            phx-value-action="check"
          >
            Check All
          </button>
          <button
            class="hw-button"
            type="button"
            phx-click="toggle_room_section"
            phx-value-room_id={@room_id}
            phx-value-section={@type}
            phx-value-action="uncheck"
          >
            Uncheck All
          </button>
        </div>
      </header>
      <p :if={@entries == []} class="hw-muted">No <%= String.downcase(@title) %></p>
      <label :for={entry <- @entries} class="hw-import-checkbox-row">
        <% source_id = fetch(entry, :source_id) %>
        <input
          type="checkbox"
          checked={ReviewPlan.selected?(@plan, @type, source_id)}
          phx-click={@event}
          phx-value-id={source_id}
        />
        <span>
          <strong><%= fetch(entry, :name) %></strong>
          <small :if={fetch(entry, :classification)}><%= fetch(entry, :classification) %></small>
        </span>
      </label>
    </section>
    """
  end

  attr(:title, :string, required: true)
  attr(:type, :atom, required: true)
  attr(:entries, :list, required: true)
  attr(:plan, :map, required: true)
  attr(:rooms, :list, required: true)

  def unassigned_entity_section(assigns) do
    assigns =
      assign(
        assigns,
        :event,
        if(assigns.type == :lights, do: "toggle_light", else: "toggle_group")
      )

    ~H"""
    <section class="hw-import-entity-section">
      <header>
        <h3><%= @title %></h3>
        <div class="hw-row-actions">
          <button
            class="hw-button"
            type="button"
            phx-click="toggle_room_section"
            phx-value-room_id="unassigned"
            phx-value-section={@type}
            phx-value-action="check"
          >
            Check All
          </button>
          <button
            class="hw-button"
            type="button"
            phx-click="toggle_room_section"
            phx-value-room_id="unassigned"
            phx-value-section={@type}
            phx-value-action="uncheck"
          >
            Uncheck All
          </button>
        </div>
      </header>
      <div :for={entry <- @entries} class="hw-import-unassigned-row">
        <% source_id = fetch(entry, :source_id) %>
        <label class="hw-import-checkbox-row">
          <input
            type="checkbox"
            checked={ReviewPlan.selected?(@plan, @type, source_id)}
            phx-click={@event}
            phx-value-id={source_id}
          />
          <span>
            <strong><%= fetch(entry, :name) %></strong>
            <small :if={fetch(entry, :classification)}><%= fetch(entry, :classification) %></small>
          </span>
        </label>
        <form
          phx-change="set_entity_room"
          class="hw-inline-form"
          data-type={@type}
          data-source-id={source_id}
        >
          <input type="hidden" name="type" value={@type} />
          <input type="hidden" name="source_id" value={source_id} />
          <label class="hw-sr-only" for={"unassigned-room-#{@type}-#{source_id}"}>HueWorks room</label>
          <select id={"unassigned-room-#{@type}-#{source_id}"} class="hw-select" name="target_room_id">
            <option value="">Unassigned</option>
            <%= for room <- @rooms do %>
              <option value={room.id} selected={ReviewPlan.entity_target_room(@plan, @type, source_id) == to_string(room.id)}>
                <%= Hueworks.Util.display_name(room) %>
              </option>
            <% end %>
          </select>
        </form>
      </div>
    </section>
    """
  end

  defp start_import(socket) do
    case pipeline_module().create_import(socket.assigns.bridge) do
      {:ok, bridge_import} ->
        normalized = bridge_import.normalized_blob

        review_blob = bridge_import.review_blob

        plan =
          review_blob
          |> Kernel.||(Plan.build_default(normalized))
          |> ReviewPlan.apply_room_merge_defaults(normalized, socket.assigns.rooms)

        socket
        |> assign(
          import_status: :ready,
          import_error: nil,
          bridge_import: bridge_import,
          normalized: normalized,
          plan: plan
        )
        |> put_notice(:info, import_flash_info(bridge_import))

      {:error, message} ->
        socket
        |> assign(import_status: :error, import_error: message)
        |> put_notice(:error, message)
    end
  end

  defp update_plan(socket, plan), do: assign(socket, plan: plan)

  defp normalized_entries(normalized, key), do: Normalize.fetch(normalized, key) || []
  defp room_action(plan, source_id), do: ReviewPlan.room_action(plan, source_id)
  defp room_merge_target(plan, source_id), do: ReviewPlan.room_merge_target(plan, source_id)

  defp pipeline_module,
    do: Application.get_env(:hueworks, :import_pipeline, Hueworks.Import.Pipeline)

  defp import_flash_info(%{status: status, imported_at: imported_at}) do
    "Configuration loaded into memory. Import status: #{status}. Imported at: #{imported_at}."
  end

  defp import_flash_info(_bridge_import), do: "Configuration loaded into memory."
end
