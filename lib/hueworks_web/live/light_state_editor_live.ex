defmodule HueworksWeb.LightStateEditorLive do
  use Phoenix.LiveView

  alias Hueworks.AppSettings
  alias Hueworks.CircadianPreview
  alias Hueworks.Scenes
  alias Hueworks.Util
  alias HueworksWeb.LightStateEditorLive.FormState

  @preview_interval_minutes 5
  @chart_width 640
  @chart_height 188
  @chart_padding %{left: 42, right: 14, top: 16, bottom: 28}

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
       save_error: nil,
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
        save_error: nil,
        dirty: true
      )
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
        {:noreply, assign(socket, save_error: message)}
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
        save_error: nil,
        dirty: false
      )
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
            FormState.default_edits(state.type, state.config || %{})
          )
          |> assign(
            light_state_usages: Scenes.light_state_usages(state.id),
            save_error: nil,
            dirty: false
          )
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
      save_error: nil,
      dirty: false
    )
    |> remember_original_state("", config)
  end

  defp assign_existing_state(socket, id) do
    case Scenes.get_editable_light_state(parse_id(id)) do
      nil ->
        push_navigate(socket, to: "/config")

      state ->
        config = FormState.default_edits(state.type, state.config || %{})

        socket
        |> assign(
          page_title: "Edit Light State",
          light_state_id: state.id,
          light_state_type: state.type,
          light_state_name: state.name,
          light_state_config: config,
          light_state_usages: Scenes.light_state_usages(state.id),
          save_error: nil,
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
    solar_config = %{
      latitude: socket.assigns.preview_latitude,
      longitude: socket.assigns.preview_longitude,
      timezone: socket.assigns.preview_timezone
    }

    case CircadianPreview.sample_day(
           socket.assigns.light_state_config,
           solar_config,
           socket.assigns.preview_date,
           interval_minutes: @preview_interval_minutes
         ) do
      {:ok, preview} ->
        assign(socket, circadian_preview: preview, circadian_preview_error: nil)

      {:error, reason} ->
        assign(
          socket,
          circadian_preview: nil,
          circadian_preview_error: preview_error_message(reason)
        )
    end
  end

  defp refresh_circadian_preview(socket) do
    assign(socket, circadian_preview: nil, circadian_preview_error: nil)
  end

  defp preview_error_message(:missing_latitude), do: "Preview needs a latitude."
  defp preview_error_message(:missing_longitude), do: "Preview needs a longitude."
  defp preview_error_message(:missing_timezone), do: "Preview needs a timezone."
  defp preview_error_message(:invalid_date), do: "Preview date must be valid."
  defp preview_error_message(:invalid_interval), do: "Preview interval must be positive."

  defp preview_error_message(:missing_coordinates),
    do: "Preview needs both latitude and longitude."

  defp preview_error_message(reason), do: "Preview unavailable: #{inspect(reason)}"

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

  defp chart_view_box, do: "0 0 #{@chart_width} #{@chart_height}"

  defp chart_path(nil, _metric), do: ""

  defp chart_path(preview, metric) do
    preview.points
    |> Enum.map(fn point ->
      value = Map.fetch!(point, metric)
      "#{x_position(point.minute)} #{y_position(value, chart_domain(preview, metric))}"
    end)
    |> case do
      [] -> ""
      [first | rest] -> "M #{first} " <> Enum.map_join(rest, " ", &"L #{&1}")
    end
  end

  defp chart_points_json(nil, _metric), do: "[]"

  defp chart_points_json(preview, metric) do
    preview.points
    |> Enum.map(fn point ->
      value = Map.fetch!(point, metric)

      %{
        minute: point.minute,
        time_label: minute_label(point.minute),
        value: value,
        value_label: chart_value_label(metric, value),
        x: x_position(point.minute),
        y: y_position(value, chart_domain(preview, metric))
      }
    end)
    |> Jason.encode!()
  end

  defp marker_x_position(minute), do: x_position(minute)

  defp x_ticks do
    [
      %{minute: 0, label: "00:00"},
      %{minute: 360, label: "06:00"},
      %{minute: 720, label: "12:00"},
      %{minute: 1080, label: "18:00"},
      %{minute: 1440, label: "24:00"}
    ]
  end

  defp y_ticks(preview, :brightness) do
    domain = chart_domain(preview, :brightness)

    [0, 25, 50, 75, 100]
    |> Enum.filter(fn value -> value >= elem(domain, 0) and value <= elem(domain, 1) end)
    |> Enum.map(&%{value: &1, label: "#{&1}%"})
  end

  defp y_ticks(preview, :kelvin) do
    {min_kelvin, max_kelvin} = chart_domain(preview, :kelvin)
    step = max(round((max_kelvin - min_kelvin) / 4 / 25) * 25, 25)

    Stream.iterate(min_kelvin, &(&1 + step))
    |> Enum.take_while(&(&1 < max_kelvin))
    |> Kernel.++([max_kelvin])
    |> Enum.uniq()
    |> Enum.map(&%{value: &1, label: "#{&1}K"})
  end

  defp marker_summary(nil, _key), do: "..."

  defp marker_summary(preview, key) do
    case Enum.find(preview.markers, &(&1.key == key)) do
      nil -> "..."
      marker -> marker.time_label
    end
  end

  defp preview_range_label(nil, _metric), do: "..."

  defp preview_range_label(preview, :brightness),
    do: "#{preview.min_brightness}% - #{preview.max_brightness}%"

  defp preview_range_label(preview, :kelvin),
    do: "#{preview.min_kelvin}K - #{preview.max_kelvin}K"

  defp chart_domain(_preview, :brightness) do
    {0, 100}
  end

  defp chart_domain(nil, :kelvin) do
    {0, 100}
  end

  defp chart_domain(preview, :kelvin) do
    min_kelvin = preview.min_kelvin
    max_kelvin = preview.max_kelvin

    if min_kelvin == max_kelvin do
      {min_kelvin - 100, max_kelvin + 100}
    else
      {min_kelvin, max_kelvin}
    end
  end

  defp plot_width, do: @chart_width - @chart_padding.left - @chart_padding.right
  defp plot_height, do: @chart_height - @chart_padding.top - @chart_padding.bottom
  defp chart_top_padding, do: @chart_padding.top
  defp chart_left_padding, do: @chart_padding.left
  defp chart_bottom_y, do: @chart_height - @chart_padding.bottom
  defp chart_x_label_y, do: @chart_height - 8

  defp minute_label(total_minutes) do
    hour = div(total_minutes, 60)
    minute = rem(total_minutes, 60)
    :io_lib.format("~2..0B:~2..0B", [hour, minute]) |> IO.iodata_to_binary()
  end

  defp chart_value_label(:brightness, value), do: "#{value}%"
  defp chart_value_label(:kelvin, value), do: "#{value}K"

  defp x_position(minute) do
    @chart_padding.left + plot_width() * minute / 1440
  end

  defp y_position(value, {min_value, max_value}) do
    ratio =
      cond do
        max_value == min_value -> 0.5
        true -> (value - min_value) / (max_value - min_value)
      end

    @chart_padding.top + plot_height() * (1 - ratio)
  end

  defp time_input_value(nil), do: ""
  defp time_input_value(""), do: ""

  defp time_input_value(value) when is_binary(value) do
    value
    |> String.trim()
    |> case do
      <<hour::binary-size(2), ?:, minute::binary-size(2), ?:, second::binary-size(2)>> ->
        "#{hour}:#{minute}:#{second}"

      <<hour::binary-size(2), ?:, minute::binary-size(2)>> ->
        "#{hour}:#{minute}:00"

      other ->
        other
    end
  end

  defp time_input_value(value) when is_integer(value), do: Integer.to_string(value)
  defp time_input_value(value) when is_float(value), do: Float.to_string(value)
  defp time_input_value(value), do: to_string(value)

  defp parse_id(value), do: Util.parse_id(value)
end
