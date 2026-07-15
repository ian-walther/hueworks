defmodule HueworksWeb.GeneralConfigLive do
  use Phoenix.LiveView

  import HueworksWeb.Notices

  alias Hueworks.AppSettings
  alias HueworksWeb.ConfigHelpers

  def mount(_params, _session, socket) do
    app_setting = AppSettings.get_global()
    timezone = app_setting.timezone || "Etc/UTC"

    {:ok,
     assign(socket,
       timezones: ConfigHelpers.timezone_options(timezone),
       latitude: ConfigHelpers.format_coord(app_setting.latitude),
       longitude: ConfigHelpers.format_coord(app_setting.longitude),
       timezone: timezone,
       default_transition_ms:
         ConfigHelpers.format_integer(app_setting.default_transition_ms || 0),
       scale_transition_by_brightness: app_setting.scale_transition_by_brightness == true
     )}
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
         ConfigHelpers.parse_boolean_param(
           Map.get(
             params,
             "scale_transition_by_brightness",
             socket.assigns.scale_transition_by_brightness
           )
         ),
       timezones: ConfigHelpers.timezone_options(timezone)
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
        ConfigHelpers.parse_boolean_param(
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
           latitude: ConfigHelpers.format_coord(app_setting.latitude),
           longitude: ConfigHelpers.format_coord(app_setting.longitude),
           timezone: app_setting.timezone,
           default_transition_ms:
             ConfigHelpers.format_integer(app_setting.default_transition_ms || 0),
           scale_transition_by_brightness: app_setting.scale_transition_by_brightness == true,
           timezones: ConfigHelpers.timezone_options(app_setting.timezone)
         )
         |> put_notice(:info, "Global solar settings saved.")}

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

  defp changeset_message(changeset) do
    changeset.errors
    |> Enum.map(fn {field, {text, _opts}} -> "#{field} #{text}" end)
    |> Enum.join(", ")
  end
end
