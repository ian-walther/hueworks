defmodule HueworksWeb.BridgeSetupLive do
  use Phoenix.LiveView

  import Hueworks.Import.Normalize, only: [fetch: 2]
  import HueworksWeb.Notices

  alias Hueworks.Bridges
  alias Hueworks.Import
  alias Hueworks.Import.{Normalize, Plan, ReviewPlan, SpaceMappings, SpaceSuggestions}
  alias Hueworks.Repo
  alias Hueworks.Schemas.{Bridge, Area}

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
         space_suggestions: nil,
         completion_summary: nil,
         areas: Repo.all(Area)
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
        socket.assigns.areas,
        action
      )

    {:noreply, update_plan(socket, plan)}
  end

  def handle_event("toggle_area", %{"area_id" => area_id, "action" => action}, socket) do
    plan =
      ReviewPlan.apply_area_toggle(
        socket.assigns.plan,
        socket.assigns.normalized,
        socket.assigns.areas,
        area_id,
        action
      )

    {:noreply, update_plan(socket, plan)}
  end

  def handle_event(
        "toggle_area_section",
        %{"area_id" => area_id, "section" => section, "action" => action},
        socket
      ) do
    plan =
      ReviewPlan.apply_area_section_toggle(
        socket.assigns.plan,
        socket.assigns.normalized,
        area_id,
        section,
        action
      )

    {:noreply, update_plan(socket, plan)}
  end

  def handle_event("set_area_action", %{"area_id" => source_id, "action" => action}, socket) do
    {:noreply,
     update_plan(
       socket,
       ReviewPlan.put_area(socket.assigns.plan, source_id, %{"action" => action})
     )}
  end

  def handle_event(
        "set_area_merge",
        %{"area_id" => source_id, "target_area_id" => target_area_id},
        socket
      ) do
    plan =
      ReviewPlan.put_area(socket.assigns.plan, source_id, %{
        "action" => "merge",
        "target_area_id" => target_area_id
      })

    {:noreply, update_plan(socket, plan)}
  end

  def handle_event(
        "set_entity_area",
        %{"type" => type, "source_id" => source_id, "target_area_id" => target_area_id},
        socket
      ) do
    plan = ReviewPlan.put_entity_area(socket.assigns.plan, type, source_id, target_area_id)
    {:noreply, update_plan(socket, plan)}
  end

  def handle_event(
        "set_space_mapping",
        %{
          "key" => key,
          "kind" => kind,
          "external_id" => external_id,
          "target_area_id" => target_area_id
        },
        socket
      ) do
    attrs = %{
      "kind" => kind,
      "external_id" => external_id,
      "action" => if(target_area_id == "", do: "skip", else: "map"),
      "target_area_id" => if(target_area_id == "", do: nil, else: target_area_id)
    }

    plan = ReviewPlan.put_space_mapping(socket.assigns.plan, key, attrs)
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
      {:ok, %{bridge: bridge, summary: summary}} ->
        {:noreply,
         socket
         |> assign(bridge: bridge, import_status: :applied, completion_summary: summary)
         |> put_notice(:info, "Bridge import applied successfully.")}

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
  attr(:area_id, :any, required: true)
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
            phx-click="toggle_area_section"
            phx-value-area_id={@area_id}
            phx-value-section={@type}
            phx-value-action="check"
          >
            Check All
          </button>
          <button
            class="hw-button"
            type="button"
            phx-click="toggle_area_section"
            phx-value-area_id={@area_id}
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
  attr(:areas, :list, required: true)

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
            phx-click="toggle_area_section"
            phx-value-area_id="unassigned"
            phx-value-section={@type}
            phx-value-action="check"
          >
            Check All
          </button>
          <button
            class="hw-button"
            type="button"
            phx-click="toggle_area_section"
            phx-value-area_id="unassigned"
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
          phx-change="set_entity_area"
          class="hw-inline-form"
          data-type={@type}
          data-source-id={source_id}
        >
          <input type="hidden" name="type" value={@type} />
          <input type="hidden" name="source_id" value={source_id} />
          <label class="hw-sr-only" for={"unassigned-area-#{@type}-#{source_id}"}>HueWorks area</label>
          <select id={"unassigned-area-#{@type}-#{source_id}"} class="hw-select" name="target_area_id">
            <option value="">Unassigned</option>
            <%= for area <- @areas do %>
              <option value={area.id} selected={ReviewPlan.entity_target_area(@plan, @type, source_id) == to_string(area.id)}>
                <%= Hueworks.Util.display_name(area) %>
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

        suggestions =
          case SpaceSuggestions.build_from_available_ha(socket.assigns.bridge, normalized) do
            {:ok, result} -> result
            {:error, _reason} -> nil
          end

        plan =
          review_blob
          |> Kernel.||(Plan.build_default(normalized))
          |> ReviewPlan.apply_area_merge_defaults(normalized, socket.assigns.areas)
          |> SpaceMappings.apply_plan_defaults(normalized)
          |> SpaceMappings.apply_suggestions(suggestions)

        socket
        |> assign(
          import_status: :ready,
          import_error: nil,
          bridge_import: bridge_import,
          normalized: normalized,
          plan: plan,
          space_suggestions: suggestions
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
  defp area_action(plan, source_id), do: ReviewPlan.area_action(plan, source_id)
  defp area_merge_target(plan, source_id), do: ReviewPlan.area_merge_target(plan, source_id)

  defp supplemental_spaces(normalized) do
    placement_keys =
      normalized
      |> normalized_entries(:areas)
      |> MapSet.new(&SpaceMappings.identity/1)

    normalized
    |> Normalize.external_spaces()
    |> Enum.reject(&MapSet.member?(placement_keys, SpaceMappings.identity(&1)))
  end

  defp space_key(space), do: space |> SpaceMappings.identity() |> SpaceMappings.key()

  defp space_suggestion(nil, _space), do: nil

  defp space_suggestion(%{spaces: suggestions}, space) do
    Map.get(suggestions, SpaceMappings.identity(space))
  end

  defp suggestion_label(:confident), do: "Matched through Home Assistant"
  defp suggestion_label(:partial), do: "Partial Home Assistant match"
  defp suggestion_label(:conflict), do: "Placement evidence conflicts"
  defp suggestion_label(:ambiguous_identity), do: "Identity match is ambiguous"
  defp suggestion_label(:no_evidence), do: "No Home Assistant match"
  defp suggestion_label(status), do: status |> to_string() |> String.replace("_", " ")

  defp suggestion_message(suggestion, areas) do
    target = area_name(areas, suggestion.suggested_area_id)

    case suggestion.status do
      :confident ->
        "#{suggestion.matched_count} of #{suggestion.member_count} members agree on #{target}; this mapping is selected for review."

      :partial ->
        "#{suggestion.matched_count} of #{suggestion.member_count} members point to #{target}; confirm it before saving."

      :conflict ->
        "Matched members or an existing mapping point to different HueWorks Areas. Choose explicitly."

      :ambiguous_identity ->
        "At least one physical identifier matches more than one Home Assistant entity. Choose explicitly."

      _ ->
        "No reliable mapped counterpart was found."
    end
  end

  defp area_name(areas, area_id) do
    case Enum.find(areas, &(&1.id == area_id)) do
      nil -> "an unavailable Area"
      area -> Hueworks.Util.display_name(area)
    end
  end

  defp space_kind_label("ha_floor"), do: "Home Assistant Floor"
  defp space_kind_label("ha_area"), do: "Home Assistant Area"
  defp space_kind_label("hue_zone"), do: "Hue Zone"
  defp space_kind_label("z2m_group"), do: "Zigbee2MQTT group"
  defp space_kind_label(kind), do: kind |> to_string() |> String.replace("_", " ")

  defp pipeline_module,
    do: Application.get_env(:hueworks, :import_pipeline, Hueworks.Import.Pipeline)

  defp import_flash_info(%{status: status, imported_at: imported_at}) do
    "Configuration loaded into memory. Import status: #{status}. Imported at: #{imported_at}."
  end

  defp import_flash_info(_bridge_import), do: "Configuration loaded into memory."
end
