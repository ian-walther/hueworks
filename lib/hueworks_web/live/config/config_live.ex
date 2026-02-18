defmodule HueworksWeb.ConfigLive do
  use Phoenix.LiveView

  alias Hueworks.AppSettings
  alias Hueworks.Bridges
  alias Hueworks.Repo
  alias Hueworks.Schemas.Bridge

  def mount(_params, _session, socket) do
    app_setting = AppSettings.get_global()

    {:ok,
     assign(socket,
       bridges: list_bridges(),
       timezones: timezone_options(),
       latitude: format_coord(app_setting.latitude),
       longitude: format_coord(app_setting.longitude),
       timezone: app_setting.timezone || "Etc/UTC",
       settings_status: nil,
       settings_error: nil
     )}
  end

  def handle_event("noop", _params, socket) do
    {:noreply, socket}
  end

  def handle_event("update_global_solar", params, socket) do
    {:noreply,
     assign(socket,
       latitude: Map.get(params, "latitude", socket.assigns.latitude),
       longitude: Map.get(params, "longitude", socket.assigns.longitude),
       timezone: Map.get(params, "timezone", socket.assigns.timezone),
       settings_status: nil,
       settings_error: nil
     )}
  end

  def handle_event("save_global_solar", params, socket) do
    attrs = %{
      latitude: Map.get(params, "latitude", socket.assigns.latitude),
      longitude: Map.get(params, "longitude", socket.assigns.longitude),
      timezone: Map.get(params, "timezone", socket.assigns.timezone)
    }

    case AppSettings.upsert_global(attrs) do
      {:ok, app_setting} ->
        {:noreply,
         socket
         |> assign(
           latitude: format_coord(app_setting.latitude),
           longitude: format_coord(app_setting.longitude),
           timezone: app_setting.timezone,
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

  def handle_event(
        "geolocation_success",
        %{"latitude" => latitude, "longitude" => longitude},
        socket
      ) do
    {:noreply,
     assign(socket,
       latitude: format_coord(latitude),
       longitude: format_coord(longitude),
       settings_status: "Location received from browser.",
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

  defp list_bridges do
    Repo.all(Bridge)
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

  defp timezone_options do
    [
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
  end
end
