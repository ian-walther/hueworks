defmodule HueworksWeb.GeneralConfigLive do
  use Phoenix.LiveView

  import HueworksWeb.Notices

  alias Hueworks.AppSettings
  alias HueworksWeb.ConfigHelpers

  def mount(params, _session, socket) do
    app_setting = AppSettings.get_global()
    timezone = app_setting.timezone || "Etc/UTC"

    {:ok,
     assign(socket,
       timezones: ConfigHelpers.timezone_options(timezone),
       latitude: ConfigHelpers.format_coord(app_setting.latitude),
       longitude: ConfigHelpers.format_coord(app_setting.longitude),
       timezone: timezone,
       postal_country_code: "US",
       postal_code: "",
       postal_lookup_status: :idle,
       default_transition_ms:
         ConfigHelpers.format_integer(
           app_setting.default_transition_ms || AppSettings.default_transition_ms()
         ),
       scale_transition_by_brightness:
         transition_scaling_value(app_setting.scale_transition_by_brightness),
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

  defp changeset_message(changeset) do
    changeset.errors
    |> Enum.map(fn {field, {text, _opts}} -> "#{field} #{text}" end)
    |> Enum.join(", ")
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
