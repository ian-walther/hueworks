defmodule HueworksWeb.ConfigLive do
  use Phoenix.LiveView

  alias Hueworks.AppSettings
  alias Hueworks.Bridges
  alias Hueworks.HomeAssistant.Export, as: HomeAssistantExport
  alias Hueworks.Repo
  alias Hueworks.Scenes
  alias Hueworks.Schemas.{Bridge, LightState}

  def mount(_params, _session, socket) do
    app_setting = AppSettings.get_global()
    timezone = app_setting.timezone || "Etc/UTC"

    {:ok,
     assign(socket,
       bridges: list_bridges(),
       light_states: list_light_states(),
       timezones: timezone_options(timezone),
       latitude: format_coord(app_setting.latitude),
       longitude: format_coord(app_setting.longitude),
       timezone: timezone,
       default_transition_ms: format_integer(app_setting.default_transition_ms || 0),
       scale_transition_by_brightness: app_setting.scale_transition_by_brightness == true,
       ha_export_scenes_enabled: app_setting.ha_export_scenes_enabled == true,
       ha_export_room_selects_enabled: app_setting.ha_export_room_selects_enabled == true,
       ha_export_lights_enabled: app_setting.ha_export_lights_enabled == true,
       ha_export_mqtt_host: app_setting.ha_export_mqtt_host || "",
       ha_export_mqtt_port: format_integer(app_setting.ha_export_mqtt_port || 1883),
       ha_export_mqtt_username: app_setting.ha_export_mqtt_username || "",
       ha_export_mqtt_password: "",
       ha_export_discovery_prefix: app_setting.ha_export_discovery_prefix || "homeassistant",
       settings_status: nil,
       settings_error: nil,
       ha_export_status: nil,
       ha_export_error: nil,
       light_state_status: nil,
       light_state_error: nil
     )}
  end

  def handle_event("noop", _params, socket) do
    {:noreply, socket}
  end

  def handle_event("update_global_solar", params, socket) do
    timezone = Map.get(params, "timezone", socket.assigns.timezone)

    {:noreply,
     assign(socket,
       latitude: Map.get(params, "latitude", socket.assigns.latitude),
       longitude: Map.get(params, "longitude", socket.assigns.longitude),
       timezone: timezone,
       default_transition_ms:
         Map.get(params, "default_transition_ms", socket.assigns.default_transition_ms),
       scale_transition_by_brightness:
         parse_boolean_param(
           Map.get(
             params,
             "scale_transition_by_brightness",
             socket.assigns.scale_transition_by_brightness
           )
         ),
       timezones: timezone_options(timezone),
       settings_status: nil,
       settings_error: nil
     )}
  end

  def handle_event("save_global_solar", params, socket) do
    attrs = %{
      latitude: Map.get(params, "latitude", socket.assigns.latitude),
      longitude: Map.get(params, "longitude", socket.assigns.longitude),
      timezone: Map.get(params, "timezone", socket.assigns.timezone),
      default_transition_ms:
        Map.get(params, "default_transition_ms", socket.assigns.default_transition_ms),
      scale_transition_by_brightness:
        parse_boolean_param(
          Map.get(
            params,
            "scale_transition_by_brightness",
            socket.assigns.scale_transition_by_brightness
          )
        )
    }

    case AppSettings.upsert_global(attrs) do
      {:ok, app_setting} ->
        {:noreply,
         socket
         |> assign(
           latitude: format_coord(app_setting.latitude),
           longitude: format_coord(app_setting.longitude),
           timezone: app_setting.timezone,
           default_transition_ms: format_integer(app_setting.default_transition_ms || 0),
           scale_transition_by_brightness: app_setting.scale_transition_by_brightness == true,
           timezones: timezone_options(app_setting.timezone),
           settings_status: "Global solar settings saved.",
           settings_error: nil
         )}

      {:error, changeset} ->
        message =
          changeset.errors
          |> Enum.map(fn {field, {text, _opts}} -> "#{field} #{text}" end)
          |> Enum.join(", ")

        {:noreply, assign(socket, settings_status: nil, settings_error: message)}
    end
  end

  def handle_event("update_ha_export", params, socket) do
    {:noreply,
     assign(socket,
       ha_export_scenes_enabled:
         parse_boolean_param(
           Map.get(
             params,
             "ha_export_scenes_enabled",
             socket.assigns.ha_export_scenes_enabled
           )
         ),
       ha_export_room_selects_enabled:
         parse_boolean_param(
           Map.get(
             params,
             "ha_export_room_selects_enabled",
             socket.assigns.ha_export_room_selects_enabled
           )
         ),
       ha_export_lights_enabled:
         parse_boolean_param(
           Map.get(params, "ha_export_lights_enabled", socket.assigns.ha_export_lights_enabled)
         ),
       ha_export_mqtt_host:
         Map.get(params, "ha_export_mqtt_host", socket.assigns.ha_export_mqtt_host),
       ha_export_mqtt_port:
         Map.get(params, "ha_export_mqtt_port", socket.assigns.ha_export_mqtt_port),
       ha_export_mqtt_username:
         Map.get(params, "ha_export_mqtt_username", socket.assigns.ha_export_mqtt_username),
       ha_export_mqtt_password:
         Map.get(params, "ha_export_mqtt_password", socket.assigns.ha_export_mqtt_password),
       ha_export_discovery_prefix:
         Map.get(
           params,
           "ha_export_discovery_prefix",
           socket.assigns.ha_export_discovery_prefix
         ),
       ha_export_status: nil,
       ha_export_error: nil
     )}
  end

  def handle_event("save_ha_export", params, socket) do
    attrs = %{
      ha_export_scenes_enabled:
        parse_boolean_param(
          Map.get(
            params,
            "ha_export_scenes_enabled",
            socket.assigns.ha_export_scenes_enabled
          )
        ),
      ha_export_room_selects_enabled:
        parse_boolean_param(
          Map.get(
            params,
            "ha_export_room_selects_enabled",
            socket.assigns.ha_export_room_selects_enabled
          )
        ),
      ha_export_lights_enabled:
        parse_boolean_param(
          Map.get(params, "ha_export_lights_enabled", socket.assigns.ha_export_lights_enabled)
        ),
      ha_export_mqtt_host:
        Map.get(params, "ha_export_mqtt_host", socket.assigns.ha_export_mqtt_host),
      ha_export_mqtt_port:
        Map.get(params, "ha_export_mqtt_port", socket.assigns.ha_export_mqtt_port),
      ha_export_mqtt_username:
        Map.get(params, "ha_export_mqtt_username", socket.assigns.ha_export_mqtt_username),
      ha_export_mqtt_password:
        Map.get(params, "ha_export_mqtt_password", socket.assigns.ha_export_mqtt_password),
      ha_export_discovery_prefix:
        Map.get(
          params,
          "ha_export_discovery_prefix",
          socket.assigns.ha_export_discovery_prefix
        )
    }

    case AppSettings.upsert_global(attrs) do
      {:ok, app_setting} ->
        HomeAssistantExport.reload()

        {:noreply,
         socket
         |> assign(
           ha_export_scenes_enabled: app_setting.ha_export_scenes_enabled == true,
           ha_export_room_selects_enabled: app_setting.ha_export_room_selects_enabled == true,
           ha_export_lights_enabled: app_setting.ha_export_lights_enabled == true,
           ha_export_mqtt_host: app_setting.ha_export_mqtt_host || "",
           ha_export_mqtt_port: format_integer(app_setting.ha_export_mqtt_port || 1883),
           ha_export_mqtt_username: app_setting.ha_export_mqtt_username || "",
           ha_export_mqtt_password: "",
           ha_export_discovery_prefix: app_setting.ha_export_discovery_prefix || "homeassistant",
           ha_export_status: "Home Assistant MQTT export settings saved.",
           ha_export_error: nil
         )}

      {:error, changeset} ->
        message =
          changeset.errors
          |> Enum.map(fn {field, {text, _opts}} -> "#{field} #{text}" end)
          |> Enum.join(", ")

        {:noreply, assign(socket, ha_export_status: nil, ha_export_error: message)}
    end
  end

  def handle_event("republish_ha_export_entities", _params, socket) do
    HomeAssistantExport.refresh_all_scenes()

    {:noreply,
     assign(socket,
       ha_export_status: "Republished exported Home Assistant entities.",
       ha_export_error: nil
     )}
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
     assign(socket,
       latitude: format_coord(latitude),
       longitude: format_coord(longitude),
       timezone: timezone,
       default_transition_ms: socket.assigns.default_transition_ms,
       scale_transition_by_brightness: socket.assigns.scale_transition_by_brightness,
       timezones: timezone_options(timezone),
       settings_status: "Location and timezone received from browser.",
       settings_error: nil
     )}
  end

  def handle_event("geolocation_error", %{"message" => message}, socket) do
    {:noreply, assign(socket, settings_status: nil, settings_error: "Location error: #{message}")}
  end

  def handle_event("delete_entities", %{"id" => id}, socket) do
    case Repo.get(Bridge, id) do
      nil ->
        {:noreply, socket}

      bridge ->
        {:ok, _} = Bridges.delete_entities(bridge)
        {:noreply, assign(socket, bridges: list_bridges())}
    end
  end

  def handle_event("delete_bridge", %{"id" => id}, socket) do
    case Repo.get(Bridge, id) do
      nil ->
        {:noreply, socket}

      bridge ->
        {:ok, _} = Bridges.delete_bridge(bridge)
        {:noreply, assign(socket, bridges: list_bridges())}
    end
  end

  def handle_event("duplicate_light_state", %{"id" => id}, socket) do
    case Scenes.duplicate_light_state(Hueworks.Util.parse_id(id)) do
      {:ok, state} ->
        {:noreply,
         socket
         |> assign(
           light_states: list_light_states(),
           light_state_status: "Duplicated #{state.name}.",
           light_state_error: nil
         )
         |> push_navigate(to: "/config/light-states/#{state.id}/edit")}

      {:error, _reason} ->
        {:noreply,
         assign(socket,
           light_state_status: nil,
           light_state_error: "Unable to duplicate light state."
         )}
    end
  end

  def handle_event("delete_light_state", %{"id" => id}, socket) do
    light_state_id = Hueworks.Util.parse_id(id)

    case Scenes.delete_light_state(light_state_id) do
      {:ok, _state} ->
        {:noreply,
         assign(socket,
           light_states: list_light_states(),
           light_state_status: "Light state deleted.",
           light_state_error: nil
         )}

      {:error, :in_use} ->
        usages =
          Scenes.light_state_usages(light_state_id)
          |> Enum.map_join(", ", fn usage -> "#{usage.room_name} / #{usage.scene_name}" end)

        {:noreply,
         assign(socket,
           light_state_status: nil,
           light_state_error: "Light state is in use by: #{usages}"
         )}

      {:error, _reason} ->
        {:noreply,
         assign(socket,
           light_state_status: nil,
           light_state_error: "Unable to delete light state."
         )}
    end
  end

  defp list_bridges do
    Repo.all(Bridge)
  end

  defp list_light_states do
    Scenes.list_editable_light_states_with_usage()
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

  defp format_integer(value) when is_integer(value), do: Integer.to_string(value)
  defp format_integer(_value), do: "0"

  defp parse_boolean_param(value) when value in [true, false], do: value
  defp parse_boolean_param("true"), do: true
  defp parse_boolean_param("false"), do: false
  defp parse_boolean_param(_value), do: false

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
      "Asia/Singapore",
      "Asia/Kolkata",
      "Australia/Sydney",
      "Australia/Melbourne",
      "Pacific/Auckland"
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

  def state_label(%{type: :circadian, name: name}), do: "#{name} (circadian)"

  def state_label(%{type: :manual, name: name, config: config}) do
    suffix =
      case LightState.manual_mode(config) do
        :color -> "manual color"
        _ -> "manual temp"
      end

    "#{name} (#{suffix})"
  end
end
