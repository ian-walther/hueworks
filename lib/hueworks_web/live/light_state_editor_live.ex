defmodule HueworksWeb.LightStateEditorLive do
  use Phoenix.LiveView

  alias Hueworks.AppSettings
  alias Hueworks.Scenes
  alias Hueworks.Util
  alias HueworksWeb.LightStateEditorLive.FormState
  alias HueworksWeb.LightStateEditorLive.Preview

  def mount(_params, _session, socket) do
    app_setting = AppSettings.get_global()
    preview_timezone = app_setting.timezone || "Etc/UTC"

    {:ok,
     assign(socket,
       page_title: "Light State",
       light_state_id: nil,
       light_state_type: :manual,
       light_state_name: "",
       light_state_config: FormState.manual_default_edits(),
       original_light_state_name: "",
       original_light_state_config: FormState.manual_default_edits(),
       light_state_usages: [],
       preview_date: FormState.default_preview_date(preview_timezone),
       preview_latitude: FormState.format_coord(app_setting.latitude),
       preview_longitude: FormState.format_coord(app_setting.longitude),
       preview_timezone: preview_timezone,
       preview_timezones: FormState.timezone_options(preview_timezone),
       original_preview_date: FormState.default_preview_date(preview_timezone),
       original_preview_latitude: FormState.format_coord(app_setting.latitude),
       original_preview_longitude: FormState.format_coord(app_setting.longitude),
       original_preview_timezone: preview_timezone,
       circadian_preview: nil,
       circadian_preview_error: nil,
       dirty: false
     )}
  end

  def handle_params(params, _uri, socket) do
    socket =
      case socket.assigns.live_action do
        :new_manual ->
          assign_new_state(socket, :manual)

        :new_circadian ->
          assign_new_state(socket, :circadian)

        :edit ->
          assign_existing_state(socket, params["id"])
      end

    {:noreply, refresh_circadian_preview(socket)}
  end

  def handle_event("update_form", params, socket) do
    {name, config} =
      FormState.merge_form_params(
        socket.assigns.light_state_type,
        socket.assigns.light_state_name,
        socket.assigns.light_state_config,
        params
      )

    preview_assigns = FormState.merge_preview_params(socket.assigns, params)

    socket =
      socket
      |> assign(
        light_state_name: name,
        light_state_config: config,
        dirty: true
      )
      |> clear_flash(:error)
      |> assign(preview_assigns)
      |> refresh_circadian_preview()

    {:noreply, socket}
  end

  def handle_event("save", params, socket) do
    {name, config} =
      FormState.merge_form_params(
        socket.assigns.light_state_type,
        socket.assigns.light_state_name,
        socket.assigns.light_state_config,
        params
      )

    save_action = normalize_save_action(Map.get(params, "save_action"))

    attrs = %{
      name: name,
      type: socket.assigns.light_state_type,
      config: config
    }

    case save_light_state(socket, attrs, save_action) do
      {:ok, updated_socket} ->
        {:noreply, updated_socket}

      {:error, message} ->
        {:noreply, put_flash(socket, :error, message)}
    end
  end

  def handle_event("revert", _params, socket) do
    socket =
      socket
      |> assign(
        light_state_name: socket.assigns.original_light_state_name,
        light_state_config: socket.assigns.original_light_state_config,
        preview_date: socket.assigns.original_preview_date,
        preview_latitude: socket.assigns.original_preview_latitude,
        preview_longitude: socket.assigns.original_preview_longitude,
        preview_timezone: socket.assigns.original_preview_timezone,
        preview_timezones: FormState.timezone_options(socket.assigns.original_preview_timezone),
        dirty: false
      )
      |> clear_flash(:error)
      |> refresh_circadian_preview()

    {:noreply, socket}
  end

  def handle_event(
        "geolocation_success",
        %{"latitude" => latitude, "longitude" => longitude} = params,
        socket
      ) do
    timezone =
      case Map.get(params, "timezone") do
        value when is_binary(value) ->
          trimmed = String.trim(value)
          if trimmed == "", do: socket.assigns.preview_timezone, else: trimmed

        _ ->
          socket.assigns.preview_timezone
      end

    socket =
      socket
      |> assign(
        preview_latitude: FormState.format_coord(latitude),
        preview_longitude: FormState.format_coord(longitude),
        preview_timezone: timezone,
        preview_timezones: FormState.timezone_options(timezone),
        circadian_preview_error: nil
      )
      |> refresh_circadian_preview()

    {:noreply, socket}
  end

  def handle_event("geolocation_error", %{"message" => message}, socket) do
    {:noreply, assign(socket, circadian_preview_error: "Location error: #{message}")}
  end

  defp save_light_state(%{assigns: %{light_state_id: nil}} = socket, attrs, action) do
    case Scenes.create_light_state(attrs.name, attrs.type, attrs.config) do
      {:ok, state} ->
        case action do
          :save_and_return ->
            {:ok, push_navigate(socket, to: "/config")}

          :save ->
            {:ok,
             socket
             |> put_flash(:info, "Light state saved.")
             |> push_patch(to: "/config/light-states/#{state.id}/edit")}
        end

      {:error, %Ecto.Changeset{} = changeset} ->
        {:error, Util.format_changeset_error(changeset)}

      {:error, _reason} ->
        {:error, "Unable to save light state."}
    end
  end

  defp save_light_state(socket, attrs, action) do
    case Scenes.update_light_state(socket.assigns.light_state_id, attrs) do
      {:ok, state} ->
        _ = Scenes.refresh_active_scenes_for_light_state(state.id)

        socket =
          socket
          |> assign_saved_snapshot(
            state.name,
            FormState.from_light_state(state)
          )
          |> assign(
            light_state_usages: Scenes.light_state_usages(state.id),
            dirty: false
          )
          |> clear_flash(:error)
          |> refresh_circadian_preview()
          |> put_flash(:info, "Light state saved.")

        case action do
          :save_and_return -> {:ok, push_navigate(socket, to: "/config")}
          :save -> {:ok, socket}
        end

      {:error, %Ecto.Changeset{} = changeset} ->
        {:error, Util.format_changeset_error(changeset)}

      {:error, _reason} ->
        {:error, "Unable to save light state."}
    end
  end

  defp assign_new_state(socket, type) do
    config = FormState.default_edits(type)

    socket
    |> assign(
      page_title: new_page_title(type),
      light_state_id: nil,
      light_state_type: type,
      light_state_name: "",
      light_state_config: config,
      light_state_usages: [],
      dirty: false
    )
    |> remember_original_state("", config)
  end

  defp assign_existing_state(socket, id) do
    case Scenes.get_editable_light_state(parse_id(id)) do
      nil ->
        push_navigate(socket, to: "/config")

      state ->
        config = FormState.from_light_state(state)

        socket
        |> assign(
          page_title: "Edit Light State",
          light_state_id: state.id,
          light_state_type: state.type,
          light_state_name: state.name,
          light_state_config: config,
          light_state_usages: Scenes.light_state_usages(state.id),
          dirty: false
        )
        |> remember_original_state(state.name, config)
    end
  end

  defp remember_original_state(socket, name, config) do
    assign(
      socket,
      original_light_state_name: name,
      original_light_state_config: config,
      original_preview_date: socket.assigns.preview_date,
      original_preview_latitude: socket.assigns.preview_latitude,
      original_preview_longitude: socket.assigns.preview_longitude,
      original_preview_timezone: socket.assigns.preview_timezone
    )
  end

  defp assign_saved_snapshot(socket, name, config) do
    assign(
      socket,
      light_state_name: name,
      light_state_config: config,
      original_light_state_name: name,
      original_light_state_config: config,
      original_preview_date: socket.assigns.preview_date,
      original_preview_latitude: socket.assigns.preview_latitude,
      original_preview_longitude: socket.assigns.preview_longitude,
      original_preview_timezone: socket.assigns.preview_timezone
    )
  end

  defp normalize_save_action("save_and_return"), do: :save_and_return
  defp normalize_save_action(_value), do: :save

  defp new_page_title(:manual), do: "New Manual Light State"
  defp new_page_title(:circadian), do: "New Circadian Light State"

  defp manual_mode(assigns) do
    FormState.manual_mode(assigns.light_state_config)
  end

  defp manual_field_value(assigns, key) do
    FormState.manual_field_value(assigns.light_state_config, key)
  end

  defp circadian_field_value(assigns, key) do
    FormState.circadian_field_value(assigns.light_state_config, key)
  end

  defp circadian_time_field_value(assigns, key) do
    FormState.circadian_time_value(assigns.light_state_config, key)
  end

  defp circadian_brightness_mode(assigns) do
    FormState.circadian_brightness_mode(assigns.light_state_config)
  end

  defp manual_color_preview_style(assigns) do
    FormState.manual_color_preview_style(assigns.light_state_config)
  end

  defp manual_color_preview_label(assigns) do
    FormState.manual_color_preview_label(assigns.light_state_config)
  end

  defp manual_saturation_scale_style(assigns) do
    FormState.manual_saturation_scale_style(assigns.light_state_config)
  end

  defp refresh_circadian_preview(%{assigns: %{light_state_type: :circadian}} = socket) do
    socket
    |> assign(
      Preview.refresh_assigns(
        :circadian,
        socket.assigns.light_state_config,
        socket.assigns.preview_date,
        socket.assigns.preview_latitude,
        socket.assigns.preview_longitude,
        socket.assigns.preview_timezone
      )
    )
  end

  defp refresh_circadian_preview(socket) do
    socket
    |> assign(Preview.refresh_assigns(:manual, nil, nil, nil, nil, nil))
  end

  attr(:label, :string, required: true)
  attr(:text, :string, required: true)

  defp help_tooltip(assigns) do
    ~H"""
    <div class="hw-help-wrap">
      <button
        type="button"
        class="hw-help-trigger"
        aria-label={"Explain #{@label}"}
        title={@text}
      >
        ?
      </button>
      <div class="hw-help-bubble" role="tooltip">
        <%= @text %>
      </div>
    </div>
    """
  end

  attr(:label, :string, required: true)
  attr(:class, :string, required: true)
  attr(:for, :string, default: nil)
  attr(:help, :string, default: nil)

  defp label_with_help(assigns) do
    ~H"""
    <div class="hw-label-with-help">
      <%= if @for do %>
        <label class={@class} for={@for}><%= @label %></label>
      <% else %>
        <div class={@class}><%= @label %></div>
      <% end %>
      <%= if @help do %>
        <.help_tooltip label={@label} text={@help} />
      <% end %>
    </div>
    """
  end

  defp help_text(:preview_date),
    do: "Samples the selected local calendar day using the preview timezone."

  defp help_text(:preview_timezone),
    do:
      "Controls the local day and local clock time used for sunrise, noon, sunset, and the chart x-axis."

  defp help_text(:preview_latitude),
    do:
      "Used for astronomical sunrise, noon, and sunset whenever fixed sunrise or sunset times are left blank."

  defp help_text(:preview_longitude),
    do:
      "Used with latitude to calculate astronomical sunrise, noon, and sunset whenever fixed times are blank."

  defp help_text(:brightness_mode),
    do:
      "Quadratic uses the original parabolic overnight ramp and clips it at max brightness during the day. Linear uses straight ramps around sunrise and sunset. Tanh uses the same windows with a softer S-curve."

  defp help_text(:brightness_range),
    do:
      "Sets the overnight floor and daytime ceiling for brightness. Every mode stays inside this range."

  defp help_text(:temperature_range),
    do:
      "Kelvin stays pinned to Min whenever the sun is at or below the horizon. During the day it rises toward Max with sun position. Ceiling is optional: it caps the finished curve after calculation, flattening the midday top while preserving the edge transitions."

  defp help_text(:sunrise_time),
    do:
      "If set, this replaces astronomical sunrise for the whole calculation. Leave blank to derive sunrise from latitude, longitude, date, and timezone."

  defp help_text(:sunrise_window),
    do:
      "After sunrise is chosen and the sunrise offset is applied, clamp the final sunrise into this min/max window."

  defp help_text(:sunrise_offset),
    do:
      "Shifts the shared sunrise event in seconds before clamping. Negative values move both curves earlier; positive values move both later."

  defp help_text(:sunset_time),
    do:
      "If set, this replaces astronomical sunset for the whole calculation. Leave blank to derive sunset from latitude, longitude, date, and timezone."

  defp help_text(:sunset_window),
    do:
      "After sunset is chosen and the sunset offset is applied, clamp the final sunset into this min/max window."

  defp help_text(:sunset_offset),
    do:
      "Shifts the shared sunset event in seconds before clamping. Negative values move both curves earlier; positive values move both later."

  defp help_text(:brightness_ramp),
    do:
      "Used only for linear and tanh. Dark is the ramp length before sunrise and after sunset. Light is the ramp length after sunrise and before sunset."

  defp help_text(:brightness_curve_offsets),
    do:
      "Shifts only the brightness curve relative to the shared solar timing above. Sunrise moves the morning transition; sunset moves the evening transition."

  defp help_text(:temperature_curve_offsets),
    do:
      "Shifts only the temperature curve relative to the shared solar timing above. Sunrise moves warming earlier or later; sunset moves cooling earlier or later."

  defp parse_id(value), do: Util.parse_id(value)
end
