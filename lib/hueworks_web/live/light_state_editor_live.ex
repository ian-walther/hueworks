defmodule HueworksWeb.LightStateEditorLive do
  use Phoenix.LiveView

  alias Hueworks.AppSettings
  alias Hueworks.Color
  alias Hueworks.Circadian.Config, as: CircadianConfig
  alias Hueworks.CircadianPreview
  alias Hueworks.Scenes
  alias Hueworks.Util

  @manual_keys ["mode", "brightness", "temperature", "hue", "saturation"]
  @preview_interval_minutes 10
  @chart_width 760
  @chart_height 240
  @chart_padding %{left: 52, right: 18, top: 18, bottom: 34}

  @circadian_numeric_fields [
    {"min_brightness", "Min Brightness (%)", 1, 100, 1},
    {"max_brightness", "Max Brightness (%)", 1, 100, 1},
    {"min_color_temp", "Min Color Temp (K)", 1000, 10000, 50},
    {"max_color_temp", "Max Color Temp (K)", 1000, 10000, 50},
    {"sunrise_offset", "Sunrise Offset (s)", -86400, 86400, 60},
    {"sunset_offset", "Sunset Offset (s)", -86400, 86400, 60},
    {"brightness_mode_time_dark", "Brightness Ramp Dark (s)", 0, 86_400, 60},
    {"brightness_mode_time_light", "Brightness Ramp Light (s)", 0, 86_400, 60}
  ]

  @circadian_time_fields [
    {"sunrise_time", "Sunrise Time"},
    {"min_sunrise_time", "Min Sunrise Time"},
    {"max_sunrise_time", "Max Sunrise Time"},
    {"sunset_time", "Sunset Time"},
    {"min_sunset_time", "Min Sunset Time"},
    {"max_sunset_time", "Max Sunset Time"}
  ]

  def mount(_params, _session, socket) do
    app_setting = AppSettings.get_global()
    preview_timezone = app_setting.timezone || "Etc/UTC"

    {:ok,
     assign(socket,
       page_title: "Light State",
       light_state_id: nil,
       light_state_type: :manual,
       light_state_name: "",
       light_state_config: manual_default_edits(),
       light_state_usages: [],
       preview_date: default_preview_date(preview_timezone),
       preview_latitude: format_coord(app_setting.latitude),
       preview_longitude: format_coord(app_setting.longitude),
       preview_timezone: preview_timezone,
       preview_timezones: timezone_options(preview_timezone),
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
    {name, config} = merge_form_params(socket, params)
    preview_assigns = merge_preview_params(socket, params)

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
    {name, config} = merge_form_params(socket, params)

    attrs = %{
      name: name,
      type: socket.assigns.light_state_type,
      config: config
    }

    case save_light_state(socket, attrs) do
      {:ok, updated_socket} ->
        {:noreply, updated_socket}

      {:error, message} ->
        {:noreply, assign(socket, save_error: message)}
    end
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
        preview_latitude: format_coord(latitude),
        preview_longitude: format_coord(longitude),
        preview_timezone: timezone,
        preview_timezones: timezone_options(timezone),
        circadian_preview_error: nil
      )
      |> refresh_circadian_preview()

    {:noreply, socket}
  end

  def handle_event("geolocation_error", %{"message" => message}, socket) do
    {:noreply, assign(socket, circadian_preview_error: "Location error: #{message}")}
  end

  defp save_light_state(%{assigns: %{light_state_id: nil}} = socket, attrs) do
    case Scenes.create_light_state(attrs.name, attrs.type, attrs.config) do
      {:ok, _state} ->
        {:ok, push_navigate(socket, to: "/config")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:error, Util.format_changeset_error(changeset)}

      {:error, _reason} ->
        {:error, "Unable to save light state."}
    end
  end

  defp save_light_state(socket, attrs) do
    case Scenes.update_light_state(socket.assigns.light_state_id, attrs) do
      {:ok, state} ->
        _ = Scenes.refresh_active_scenes_for_light_state(state.id)
        {:ok, push_navigate(socket, to: "/config")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:error, Util.format_changeset_error(changeset)}

      {:error, _reason} ->
        {:error, "Unable to save light state."}
    end
  end

  defp assign_new_state(socket, type) do
    assign(socket,
      page_title: new_page_title(type),
      light_state_id: nil,
      light_state_type: type,
      light_state_name: "",
      light_state_config: default_edits(type),
      light_state_usages: [],
      save_error: nil,
      dirty: false
    )
  end

  defp assign_existing_state(socket, id) do
    case Scenes.get_editable_light_state(parse_id(id)) do
      nil ->
        push_navigate(socket, to: "/config")

      state ->
        assign(socket,
          page_title: "Edit Light State",
          light_state_id: state.id,
          light_state_type: state.type,
          light_state_name: state.name,
          light_state_config: default_edits(state.type, state.config || %{}),
          light_state_usages: Scenes.light_state_usages(state.id),
          save_error: nil,
          dirty: false
        )
    end
  end

  defp new_page_title(:manual), do: "New Manual Light State"
  defp new_page_title(:circadian), do: "New Circadian Light State"

  defp default_edits(type, config \\ %{})
  defp default_edits(:manual, config), do: manual_default_edits(config)
  defp default_edits(:circadian, config), do: circadian_default_edits(config)

  defp manual_default_edits(config \\ %{}) do
    %{
      "mode" => manual_mode_from_config(config),
      "brightness" => config_value(config, "brightness"),
      "temperature" => config_value(config, "temperature"),
      "hue" => config_value(config, "hue"),
      "saturation" => config_value(config, "saturation")
    }
  end

  defp circadian_default_edits(config) do
    defaults =
      CircadianConfig.defaults()
      |> Enum.map(fn {key, value} -> {key, stringify_config_value(value)} end)
      |> Map.new()

    Enum.reduce(config, defaults, fn {key, value}, acc ->
      normalized_key = normalize_config_key(key)

      if normalized_key in circadian_form_keys() do
        Map.put(acc, normalized_key, stringify_config_value(value))
      else
        acc
      end
    end)
  end

  defp circadian_form_keys, do: CircadianConfig.supported_keys()
  defp circadian_numeric_fields, do: @circadian_numeric_fields
  defp circadian_time_fields, do: @circadian_time_fields

  defp stringify_config_value(nil), do: ""
  defp stringify_config_value(value) when is_binary(value), do: value
  defp stringify_config_value(value) when is_integer(value), do: Integer.to_string(value)
  defp stringify_config_value(value) when is_float(value), do: Float.to_string(value)
  defp stringify_config_value(value), do: to_string(value)

  defp normalize_config_key(key) when is_atom(key), do: Atom.to_string(key)
  defp normalize_config_key(key) when is_binary(key), do: key
  defp normalize_config_key(key), do: to_string(key)

  defp config_value(config, key) do
    case config_lookup(config, key) do
      nil -> ""
      value -> value
    end
  end

  defp config_lookup(config, key) do
    cond do
      is_map(config) and Map.has_key?(config, key) ->
        Map.get(config, key)

      true ->
        atom_key = key_to_atom(key)

        if atom_key && is_map(config) && Map.has_key?(config, atom_key) do
          Map.get(config, atom_key)
        else
          nil
        end
    end
  end

  defp key_to_atom("brightness"), do: :brightness
  defp key_to_atom("temperature"), do: :temperature
  defp key_to_atom("hue"), do: :hue
  defp key_to_atom("saturation"), do: :saturation
  defp key_to_atom("mode"), do: :mode
  defp key_to_atom("min_brightness"), do: :min_brightness
  defp key_to_atom("max_brightness"), do: :max_brightness
  defp key_to_atom("min_color_temp"), do: :min_color_temp
  defp key_to_atom("max_color_temp"), do: :max_color_temp
  defp key_to_atom("sunrise_time"), do: :sunrise_time
  defp key_to_atom("min_sunrise_time"), do: :min_sunrise_time
  defp key_to_atom("max_sunrise_time"), do: :max_sunrise_time
  defp key_to_atom("sunrise_offset"), do: :sunrise_offset
  defp key_to_atom("sunset_time"), do: :sunset_time
  defp key_to_atom("min_sunset_time"), do: :min_sunset_time
  defp key_to_atom("max_sunset_time"), do: :max_sunset_time
  defp key_to_atom("sunset_offset"), do: :sunset_offset
  defp key_to_atom("brightness_mode"), do: :brightness_mode
  defp key_to_atom("brightness_mode_time_dark"), do: :brightness_mode_time_dark
  defp key_to_atom("brightness_mode_time_light"), do: :brightness_mode_time_light
  defp key_to_atom(_key), do: nil

  defp manual_mode_from_config(config) do
    case config_lookup(config || %{}, "mode") do
      "color" -> "color"
      :color -> "color"
      _ -> "temperature"
    end
  end

  defp manual_mode(assigns) do
    case Map.get(assigns.light_state_config, "mode") do
      "color" -> "color"
      :color -> "color"
      _ -> "temperature"
    end
  end

  defp manual_color_preview_style(assigns) do
    {r, g, b} = manual_color_rgb(assigns) || {143, 177, 255}
    "background-color: rgb(#{r} #{g} #{b});"
  end

  defp manual_color_preview_label(assigns) do
    hue = Map.get(assigns.light_state_config, "hue") |> normalize_preview_number(0)

    saturation =
      Map.get(assigns.light_state_config, "saturation") |> normalize_preview_number(100)

    brightness =
      Map.get(assigns.light_state_config, "brightness") |> normalize_preview_number(100)

    "Preview: #{hue}°, #{saturation}% saturation, #{brightness}% brightness"
  end

  defp manual_saturation_scale_style(assigns) do
    hue = Map.get(assigns.light_state_config, "hue") |> normalize_preview_number(0)

    brightness =
      Map.get(assigns.light_state_config, "brightness") |> normalize_preview_number(100)

    {r1, g1, b1} = Color.hsb_to_rgb(hue, 0, brightness) || {255, 255, 255}
    {r2, g2, b2} = Color.hsb_to_rgb(hue, 100, brightness) || {255, 255, 255}

    "background: linear-gradient(90deg, rgb(#{r1} #{g1} #{b1}), rgb(#{r2} #{g2} #{b2}));"
  end

  defp manual_color_rgb(assigns) do
    Color.hsb_to_rgb(
      Map.get(assigns.light_state_config, "hue"),
      Map.get(assigns.light_state_config, "saturation"),
      Map.get(assigns.light_state_config, "brightness")
    )
  end

  defp normalize_preview_number(value, fallback) do
    case Util.to_number(value) do
      number when is_number(number) -> round(number)
      _ -> fallback
    end
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

  defp chart_view_box, do: "0 0 #{@chart_width} #{@chart_height}"

  defp chart_path(nil, _metric), do: ""

  defp chart_path(preview, metric) do
    preview.points
    |> Enum.map(fn point ->
      "#{x_position(point.minute)} #{y_position(point[metric], chart_domain(preview, metric))}"
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
      value = point[metric]

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

  defp marker_summary(nil, _key), do: "—"

  defp marker_summary(preview, key) do
    case Enum.find(preview.markers, &(&1.key == key)) do
      nil -> "—"
      marker -> marker.time_label
    end
  end

  defp chart_domain(_preview, :brightness) do
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

  defp time_input_value(value), do: stringify_config_value(value)

  defp parse_id(value), do: Util.parse_id(value)

  defp merge_form_params(socket, params) do
    name = Map.get(params, "name", socket.assigns.light_state_name)

    config =
      case socket.assigns.light_state_type do
        :manual ->
          Enum.reduce(@manual_keys, socket.assigns.light_state_config, fn key, acc ->
            if Map.has_key?(params, key) do
              Map.put(acc, key, Map.get(params, key))
            else
              acc
            end
          end)
          |> Map.put_new("mode", "temperature")

        :circadian ->
          Enum.reduce(circadian_form_keys(), socket.assigns.light_state_config, fn key, acc ->
            if Map.has_key?(params, key) do
              Map.put(acc, key, Map.get(params, key))
            else
              acc
            end
          end)
      end

    {name, config}
  end

  defp merge_preview_params(socket, params) do
    timezone = Map.get(params, "preview_timezone", socket.assigns.preview_timezone)

    %{
      preview_date: Map.get(params, "preview_date", socket.assigns.preview_date),
      preview_latitude: Map.get(params, "preview_latitude", socket.assigns.preview_latitude),
      preview_longitude: Map.get(params, "preview_longitude", socket.assigns.preview_longitude),
      preview_timezone: timezone,
      preview_timezones: timezone_options(timezone)
    }
  end

  defp default_preview_date(timezone) do
    case DateTime.now(timezone) do
      {:ok, datetime} -> Date.to_iso8601(DateTime.to_date(datetime))
      {:error, _reason} -> Date.to_iso8601(Date.utc_today())
    end
  end

  defp format_coord(nil), do: ""

  defp format_coord(value) when is_binary(value) do
    case Float.parse(value) do
      {number, _} -> format_coord(number)
      :error -> ""
    end
  end

  defp format_coord(value) when is_integer(value), do: format_coord(value * 1.0)
  defp format_coord(value) when is_float(value), do: :erlang.float_to_binary(value, decimals: 6)
  defp format_coord(_value), do: ""

  defp timezone_options(current_timezone) do
    base_timezones = [
      "Etc/UTC",
      "America/New_York",
      "America/Chicago",
      "America/Denver",
      "America/Los_Angeles",
      "America/Phoenix",
      "America/Anchorage",
      "Pacific/Honolulu",
      "Europe/London",
      "Europe/Paris",
      "Europe/Berlin",
      "Europe/Madrid",
      "Europe/Rome",
      "Asia/Tokyo",
      "Asia/Seoul",
      "Asia/Shanghai",
      "Australia/Sydney"
    ]

    case normalize_timezone(current_timezone) do
      nil -> base_timezones
      timezone -> Enum.uniq([timezone | base_timezones])
    end
  end

  defp normalize_timezone(value) when is_binary(value) do
    trimmed = String.trim(value)
    if trimmed == "", do: nil, else: trimmed
  end

  defp normalize_timezone(_value), do: nil
end
