defmodule HueworksWeb.ConfigLive do
  use Phoenix.LiveView

  import HueworksWeb.Notices

  alias Hueworks.AppSettings
  alias Hueworks.Bridges
  alias Hueworks.HomeKit
  alias Hueworks.Onboarding

  def mount(_params, _session, socket) do
    app_setting = AppSettings.get_global()
    bridges = Bridges.list_bridges()
    light_states = Hueworks.Scenes.list_editable_light_states_with_usage()
    pending_bridges = Enum.count(bridges, &(not Bridges.imported?(&1)))
    health = Hueworks.Health.status()

    onboarding = Onboarding.status()

    {:ok,
     assign(socket,
       app_setting: app_setting,
       bridge_count: length(bridges),
       pending_bridge_count: pending_bridges,
       light_state_count: length(light_states),
       onboarding: onboarding,
       show_setup_callout?: not onboarding.finished? and not onboarding.dismissed?,
       homekit_paired?: HomeKit.paired?(),
       general_configured?: configured_location?(app_setting),
       ha_enabled?: ha_enabled?(app_setting),
       homekit_enabled?: app_setting.homekit_scenes_enabled == true,
       api_enabled?: AppSettings.api_enabled?(),
       health: health.body,
       healthy?: health.ready?
     )}
  end

  def handle_event("dismiss_setup", _params, socket) do
    case Onboarding.dismiss() do
      {:ok, _settings} ->
        {:noreply,
         socket
         |> assign(show_setup_callout?: false, onboarding: Onboarding.status())
         |> put_notice(:info, "Setup guide dismissed. Your configuration was kept.")}

      {:error, _changeset} ->
        {:noreply, put_notice(socket, :error, "Setup guide could not be dismissed.")}
    end
  end

  defp configured_location?(app_setting) do
    is_number(app_setting.latitude) and is_number(app_setting.longitude) and
      is_binary(app_setting.timezone) and app_setting.timezone != ""
  end

  defp ha_enabled?(app_setting) do
    app_setting.ha_export_scenes_enabled == true or
      app_setting.ha_export_area_selects_enabled == true or
      app_setting.ha_export_lights_enabled == true
  end
end
