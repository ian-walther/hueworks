defmodule HueworksWeb.IntegrationsConfigLive do
  use Phoenix.LiveView

  import HueworksWeb.Notices

  alias Hueworks.AppSettings
  alias Hueworks.HomeAssistant.Export, as: HomeAssistantExport
  alias Hueworks.HomeKit
  alias HueworksWeb.ConfigHelpers

  def mount(_params, _session, socket) do
    app_setting = AppSettings.get_global()

    {:ok,
     assign(socket,
       ha_export_scenes_enabled: app_setting.ha_export_scenes_enabled == true,
       ha_export_area_selects_enabled: app_setting.ha_export_area_selects_enabled == true,
       ha_export_lights_enabled: app_setting.ha_export_lights_enabled == true,
       ha_export_mqtt_host: app_setting.ha_export_mqtt_host || "",
       ha_export_mqtt_port: ConfigHelpers.format_integer(app_setting.ha_export_mqtt_port || 1883),
       ha_export_mqtt_username: app_setting.ha_export_mqtt_username || "",
       ha_export_mqtt_password: "",
       ha_export_discovery_prefix: app_setting.ha_export_discovery_prefix || "homeassistant",
       homekit_scenes_enabled: app_setting.homekit_scenes_enabled == true,
       homekit_bridge_name: app_setting.homekit_bridge_name || "HueWorks",
       homekit_pairing_code: ConfigHelpers.homekit_pairing_code(app_setting),
       homekit_paired?: HomeKit.paired?(),
       homekit_runtime_status: HomeKit.runtime_status(),
       api_enabled: AppSettings.api_enabled?(),
       api_token: nil,
       api_token_revealed?: false,
       api_base_url: ConfigHelpers.api_base_url()
     )}
  end

  def handle_event("update_ha_export", params, socket) do
    {:noreply,
     assign(socket,
       ha_export_scenes_enabled: boolean_param(params, "ha_export_scenes_enabled", socket),
       ha_export_area_selects_enabled:
         boolean_param(params, "ha_export_area_selects_enabled", socket),
       ha_export_lights_enabled: boolean_param(params, "ha_export_lights_enabled", socket),
       ha_export_mqtt_host:
         Map.get(params, "ha_export_mqtt_host", socket.assigns.ha_export_mqtt_host),
       ha_export_mqtt_port:
         Map.get(params, "ha_export_mqtt_port", socket.assigns.ha_export_mqtt_port),
       ha_export_mqtt_username:
         Map.get(params, "ha_export_mqtt_username", socket.assigns.ha_export_mqtt_username),
       ha_export_mqtt_password:
         Map.get(params, "ha_export_mqtt_password", socket.assigns.ha_export_mqtt_password),
       ha_export_discovery_prefix:
         Map.get(params, "ha_export_discovery_prefix", socket.assigns.ha_export_discovery_prefix)
     )}
  end

  def handle_event("save_ha_export", params, socket) do
    attrs =
      %{
        ha_export_scenes_enabled: boolean_param(params, "ha_export_scenes_enabled", socket),
        ha_export_area_selects_enabled:
          boolean_param(params, "ha_export_area_selects_enabled", socket),
        ha_export_lights_enabled: boolean_param(params, "ha_export_lights_enabled", socket),
        ha_export_mqtt_host:
          Map.get(params, "ha_export_mqtt_host", socket.assigns.ha_export_mqtt_host),
        ha_export_mqtt_port:
          Map.get(params, "ha_export_mqtt_port", socket.assigns.ha_export_mqtt_port),
        ha_export_mqtt_username:
          Map.get(params, "ha_export_mqtt_username", socket.assigns.ha_export_mqtt_username),
        ha_export_mqtt_password:
          Map.get(params, "ha_export_mqtt_password", socket.assigns.ha_export_mqtt_password),
        ha_export_discovery_prefix:
          Map.get(params, "ha_export_discovery_prefix", socket.assigns.ha_export_discovery_prefix)
      }
      |> keep_existing_ha_export_password_on_blank()

    case AppSettings.upsert_global(attrs) do
      {:ok, app_setting} ->
        HomeAssistantExport.reload()

        {:noreply,
         socket
         |> assign(
           ha_export_scenes_enabled: app_setting.ha_export_scenes_enabled == true,
           ha_export_area_selects_enabled: app_setting.ha_export_area_selects_enabled == true,
           ha_export_lights_enabled: app_setting.ha_export_lights_enabled == true,
           ha_export_mqtt_host: app_setting.ha_export_mqtt_host || "",
           ha_export_mqtt_port:
             ConfigHelpers.format_integer(app_setting.ha_export_mqtt_port || 1883),
           ha_export_mqtt_username: app_setting.ha_export_mqtt_username || "",
           ha_export_mqtt_password: "",
           ha_export_discovery_prefix: app_setting.ha_export_discovery_prefix || "homeassistant"
         )
         |> put_notice(:info, "Home Assistant MQTT export settings saved.")}

      {:error, changeset} ->
        {:noreply, put_notice(socket, :error, changeset_message(changeset))}
    end
  end

  def handle_event("republish_ha_export_entities", _params, socket) do
    HomeAssistantExport.refresh_all_scenes()
    {:noreply, put_notice(socket, :info, "Republished exported Home Assistant entities.")}
  end

  def handle_event("update_homekit", params, socket) do
    {:noreply,
     assign(socket,
       homekit_scenes_enabled: boolean_param(params, "homekit_scenes_enabled", socket),
       homekit_bridge_name:
         Map.get(params, "homekit_bridge_name", socket.assigns.homekit_bridge_name)
     )}
  end

  def handle_event("save_homekit", params, socket) do
    attrs = %{
      homekit_scenes_enabled: boolean_param(params, "homekit_scenes_enabled", socket),
      homekit_bridge_name:
        Map.get(params, "homekit_bridge_name", socket.assigns.homekit_bridge_name)
    }

    case AppSettings.upsert_global(attrs) do
      {:ok, app_setting} ->
        HomeKit.reload()

        {:noreply,
         socket
         |> assign(
           homekit_scenes_enabled: app_setting.homekit_scenes_enabled == true,
           homekit_bridge_name: app_setting.homekit_bridge_name || "HueWorks",
           homekit_pairing_code: ConfigHelpers.homekit_pairing_code(app_setting)
         )
         |> put_notice(:info, "HomeKit bridge settings saved.")}

      {:error, changeset} ->
        {:noreply, put_notice(socket, :error, changeset_message(changeset))}
    end
  end

  def handle_event("reset_homekit_pairings", _params, socket) do
    case HomeKit.reset_pairings() do
      {:ok, count} ->
        message =
          case count do
            0 ->
              "HomeKit bridge had no saved pairings."

            1 ->
              "Reset 1 HomeKit pairing. Remove HueWorks from Apple Home, then add it again."

            n ->
              "Reset #{n} HomeKit pairings. Remove HueWorks from Apple Home, then add it again."
          end

        {:noreply,
         socket
         |> assign(homekit_paired?: HomeKit.paired?())
         |> assign(homekit_runtime_status: HomeKit.runtime_status())
         |> put_notice(:info, message)}

      {:error, reason} ->
        {:noreply,
         put_notice(socket, :error, "Unable to reset HomeKit pairings: #{inspect(reason)}")}
    end
  end

  def handle_event("enable_api_access", _params, socket) do
    case AppSettings.enable_api_access() do
      {:ok, _app_setting} ->
        {:noreply,
         socket
         |> assign(api_enabled: true, api_token: nil, api_token_revealed?: false)
         |> put_notice(:info, "AI API access enabled. Reveal the token to configure MCP.")}

      {:error, _reason} ->
        {:noreply, put_notice(socket, :error, "Unable to enable AI API access.")}
    end
  end

  def handle_event("disable_api_access", _params, socket) do
    case AppSettings.disable_api_access() do
      {:ok, _app_setting} ->
        {:noreply,
         socket
         |> assign(api_enabled: false, api_token: nil, api_token_revealed?: false)
         |> put_notice(:info, "AI API access disabled.")}

      {:error, _reason} ->
        {:noreply, put_notice(socket, :error, "Unable to disable AI API access.")}
    end
  end

  def handle_event("reveal_api_token", _params, socket) do
    {:noreply, assign(socket, api_token: AppSettings.api_token(), api_token_revealed?: true)}
  end

  def handle_event("hide_api_token", _params, socket) do
    {:noreply, assign(socket, api_token: nil, api_token_revealed?: false)}
  end

  def handle_event("rotate_api_token", _params, socket) do
    case AppSettings.rotate_api_token() do
      {:ok, app_setting} ->
        {:noreply,
         socket
         |> assign(api_token: app_setting.api_token, api_token_revealed?: true)
         |> put_notice(
           :info,
           "API token rotated. Update the MCP configuration before using it again."
         )}

      {:error, :api_disabled} ->
        {:noreply, put_notice(socket, :error, "Enable AI API access before rotating its token.")}

      {:error, _reason} ->
        {:noreply, put_notice(socket, :error, "Unable to rotate the API token.")}
    end
  end

  defp boolean_param(params, key, socket) do
    ConfigHelpers.parse_boolean_param(
      Map.get(params, key, Map.fetch!(socket.assigns, String.to_existing_atom(key)))
    )
  end

  defp keep_existing_ha_export_password_on_blank(%{ha_export_mqtt_password: ""} = attrs),
    do: Map.delete(attrs, :ha_export_mqtt_password)

  defp keep_existing_ha_export_password_on_blank(attrs), do: attrs

  defp changeset_message(changeset) do
    changeset.errors
    |> Enum.map(fn {field, {text, _opts}} -> "#{field} #{text}" end)
    |> Enum.join(", ")
  end
end
