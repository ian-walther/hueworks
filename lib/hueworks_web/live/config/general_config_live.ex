defmodule HueworksWeb.GeneralConfigLive do
  use Phoenix.LiveView

  import HueworksWeb.Notices

  alias Hueworks.AppSettings
  alias Hueworks.Circadian.Config, as: CircadianConfig
  alias Hueworks.Circadian.Timing
  alias Hueworks.DomainEvents
  alias HueworksWeb.ConfigHelpers
  alias Phoenix.PubSub

  @timing_fields Timing.window_fields()
  @form_fields [
    :latitude,
    :longitude,
    :timezone,
    :default_transition_ms,
    :scale_transition_by_brightness | @timing_fields
  ]
  @timing_labels %{
    min_sunrise_time: "Sunrise minimum",
    max_sunrise_time: "Sunrise maximum",
    min_sunset_time: "Sunset minimum",
    max_sunset_time: "Sunset maximum"
  }

  def mount(params, _session, socket) do
    if connected?(socket), do: PubSub.subscribe(Hueworks.PubSub, DomainEvents.topic())

    app_setting = AppSettings.get_global()
    timezone = app_setting.timezone || "Etc/UTC"
    persisted = persisted_form_values(app_setting)

    {:ok,
     assign(socket,
       timezones: ConfigHelpers.timezone_options(timezone),
       latitude: persisted.latitude,
       longitude: persisted.longitude,
       timezone: timezone,
       postal_country_code: "US",
       postal_code: "",
       postal_lookup_status: :idle,
       default_transition_ms: persisted.default_transition_ms,
       scale_transition_by_brightness: persisted.scale_transition_by_brightness,
       min_sunrise_time: persisted.min_sunrise_time,
       max_sunrise_time: persisted.max_sunrise_time,
       min_sunset_time: persisted.min_sunset_time,
       max_sunset_time: persisted.max_sunset_time,
       persisted_form: persisted,
       exit_path: exit_path(params)
     )}
  end

  def handle_event("lookup_postal_code", params, socket) do
    country_code = Map.get(params, "country_code", "") |> String.trim() |> String.upcase()
    postal_code = Map.get(params, "postal_code", "") |> String.trim()

    {:noreply,
     socket
     |> assign(
       postal_country_code: country_code,
       postal_code: postal_code,
       postal_lookup_status: :loading
     )
     |> start_async(:postal_code_lookup, fn ->
       postal_code_lookup_module().lookup(country_code, postal_code)
     end)}
  end

  def handle_event("update_global_solar", params, socket) do
    values = form_values(params, socket.assigns)

    {:noreply,
     socket
     |> assign(values)
     |> assign(timezones: ConfigHelpers.timezone_options(values.timezone))}
  end

  def handle_event("save_global_solar", params, socket) do
    attrs =
      params
      |> form_values(socket.assigns)
      |> edited_values(socket.assigns.persisted_form)

    case AppSettings.upsert_global(attrs) do
      {:ok, app_setting} ->
        {:noreply,
         socket
         |> assign(
           latitude: ConfigHelpers.format_coord(app_setting.latitude),
           longitude: ConfigHelpers.format_coord(app_setting.longitude),
           timezone: app_setting.timezone,
           default_transition_ms:
             ConfigHelpers.format_integer(app_setting.default_transition_ms || 0),
           scale_transition_by_brightness: app_setting.scale_transition_by_brightness == true,
           timezones: ConfigHelpers.timezone_options(app_setting.timezone)
         )
         |> push_navigate(to: socket.assigns.exit_path)}

      {:error, changeset} ->
        {:noreply, put_notice(socket, :error, changeset_message(changeset))}
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
          if trimmed == "", do: socket.assigns.timezone, else: trimmed

        _ ->
          socket.assigns.timezone
      end

    {:noreply,
     socket
     |> assign(
       latitude: ConfigHelpers.format_coord(latitude),
       longitude: ConfigHelpers.format_coord(longitude),
       timezone: timezone,
       timezones: ConfigHelpers.timezone_options(timezone)
     )
     |> put_notice(:info, "Location and timezone received from browser.")}
  end

  def handle_event("geolocation_error", %{"message" => message}, socket) do
    {:noreply, put_notice(socket, :error, "Location error: #{message}")}
  end

  def handle_async(:postal_code_lookup, {:ok, {:ok, location}}, socket) do
    {:noreply,
     socket
     |> assign(
       latitude: ConfigHelpers.format_coord(location.latitude),
       longitude: ConfigHelpers.format_coord(location.longitude),
       postal_lookup_status: :idle
     )
     |> put_notice(:info, "Coordinates found for #{location_label(location)}.")}
  end

  def handle_async(:postal_code_lookup, {:ok, {:error, reason}}, socket) do
    {:noreply,
     socket
     |> assign(postal_lookup_status: :idle)
     |> put_notice(:error, postal_lookup_error(reason))}
  end

  def handle_async(:postal_code_lookup, {:exit, _reason}, socket) do
    {:noreply,
     socket
     |> assign(postal_lookup_status: :idle)
     |> put_notice(:error, postal_lookup_error(:temporarily_unavailable))}
  end

  # A Home Assistant or other tab's commit appears here unless this form has its
  # own unsaved edit of that field, which saving later patches over the latest.
  def handle_info({:global_settings_changed, _fields}, socket) do
    persisted = persisted_form_values(AppSettings.get_global())

    refreshed =
      @form_fields
      |> Enum.filter(
        &same_value?(&1, Map.fetch!(socket.assigns, &1), socket.assigns.persisted_form[&1])
      )
      |> Map.new(&{&1, Map.fetch!(persisted, &1)})

    socket =
      socket
      |> assign(refreshed)
      |> assign(persisted_form: persisted)

    {:noreply, assign(socket, timezones: ConfigHelpers.timezone_options(socket.assigns.timezone))}
  end

  def handle_info(_message, socket), do: {:noreply, socket}

  defp form_values(params, assigns) do
    @form_fields
    |> Map.new(&{&1, Map.get(params, Atom.to_string(&1), Map.fetch!(assigns, &1))})
    |> Map.update!(:scale_transition_by_brightness, &ConfigHelpers.parse_boolean_param/1)
  end

  defp persisted_form_values(app_setting) do
    timing_values = Map.new(@timing_fields, &{&1, Map.fetch!(app_setting, &1) || ""})

    Map.merge(timing_values, %{
      latitude: ConfigHelpers.format_coord(app_setting.latitude),
      longitude: ConfigHelpers.format_coord(app_setting.longitude),
      timezone: app_setting.timezone || "",
      default_transition_ms:
        ConfigHelpers.format_integer(
          app_setting.default_transition_ms || AppSettings.default_transition_ms()
        ),
      scale_transition_by_brightness:
        transition_scaling_value(app_setting.scale_transition_by_brightness)
    })
  end

  defp edited_values(values, persisted) do
    values
    |> Enum.reject(fn {field, value} -> same_value?(field, value, persisted[field]) end)
    |> Map.new()
  end

  defp same_value?(field, value, persisted) when field in @timing_fields do
    CircadianConfig.normalize_wall_clock_time(value) ==
      CircadianConfig.normalize_wall_clock_time(persisted)
  end

  defp same_value?(_field, value, persisted), do: value == persisted

  defp changeset_message(changeset) do
    Enum.map_join(changeset.errors, ", ", fn {field, {text, _opts}} ->
      "#{field_label(field)} #{timing_labels_in(text)}"
    end)
  end

  defp field_label(field), do: Map.get(@timing_labels, field, field)

  defp timing_labels_in(text) do
    Enum.reduce(@timing_labels, text, fn {field, label}, acc ->
      String.replace(acc, Atom.to_string(field), String.downcase(label))
    end)
  end

  defp exit_path(%{"return_to" => "setup"}), do: "/setup"
  defp exit_path(_params), do: "/config"

  defp transition_scaling_value(value) when is_boolean(value), do: value

  defp transition_scaling_value(_value),
    do: AppSettings.default_scale_transition_by_brightness?()

  defp location_label(location) do
    [location.place_name, location.region, location.country]
    |> Enum.filter(&(is_binary(&1) and &1 != ""))
    |> Enum.uniq()
    |> Enum.take(2)
    |> case do
      [] -> "the requested postal code"
      parts -> Enum.join(parts, ", ")
    end
  end

  defp postal_lookup_error(:invalid_country_code),
    do: "Enter a two-letter country code."

  defp postal_lookup_error(:invalid_postal_code), do: "Enter a ZIP or postal code."
  defp postal_lookup_error(:not_found), do: "That ZIP or postal code was not found."

  defp postal_lookup_error(:temporarily_unavailable),
    do: "Postal code lookup is temporarily unavailable. Enter coordinates manually or try again."

  defp postal_lookup_error(_reason),
    do: "Postal code lookup failed. Enter coordinates manually or try again."

  defp postal_code_lookup_module do
    Application.get_env(
      :hueworks,
      :postal_code_lookup_module,
      Hueworks.Location.PostalCodeLookup
    )
  end
end
