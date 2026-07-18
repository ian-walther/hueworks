defmodule HueworksWeb.ConfigLive do
  use Phoenix.LiveView

  alias Hueworks.AppSettings
  alias Hueworks.Bridges
  alias Hueworks.HomeKit
  alias Hueworks.Areas
  alias Hueworks.Scenes

  def mount(_params, _session, socket) do
    app_setting = AppSettings.get_global()
    bridges = Bridges.list_bridges()
    light_states = Scenes.list_editable_light_states_with_usage()
    areas = Areas.list_areas_with_children()
    pending_bridges = Enum.count(bridges, &(not Bridges.imported?(&1)))
    scene_count = Enum.sum(Enum.map(areas, &length(&1.scenes)))
    health = Hueworks.Health.status()

    setup_steps =
      setup_steps(
        configured_location?(app_setting),
        length(bridges),
        pending_bridges,
        length(areas),
        scene_count
      )

    {:ok,
     assign(socket,
       app_setting: app_setting,
       bridge_count: length(bridges),
       pending_bridge_count: pending_bridges,
       light_state_count: length(light_states),
       setup_steps: setup_steps,
       setup_complete?: Enum.all?(setup_steps, & &1.complete?),
       homekit_paired?: HomeKit.paired?(),
       general_configured?: configured_location?(app_setting),
       ha_enabled?: ha_enabled?(app_setting),
       homekit_enabled?: app_setting.homekit_scenes_enabled == true,
       api_enabled?: AppSettings.api_enabled?(),
       health: health.body,
       healthy?: health.ready?
     )}
  end

  defp setup_steps(
         general_configured?,
         bridge_count,
         pending_bridge_count,
         area_count,
         scene_count
       ) do
    [
      %{
        id: "general",
        title: "Set location",
        description: "Choose the timezone and location used by solar and circadian behavior.",
        href: "/config/general",
        action: "Open General",
        complete?: general_configured?
      },
      %{
        id: "bridges",
        title: "Add a bridge",
        description:
          "Connect native Hue, Caseta, and Zigbee2MQTT sources before Home Assistant whenever possible.",
        href: "/config/bridges",
        action: "Open Bridges",
        complete?: bridge_count > 0
      },
      %{
        id: "import",
        title: "Import entities",
        description: "Review and apply the initial import for every configured bridge.",
        href: "/config/bridges",
        action: "Review Imports",
        complete?: bridge_count > 0 and pending_bridge_count == 0
      },
      %{
        id: "areas",
        title: "Review areas",
        description: "Confirm imported lights and groups are organized the way you control them.",
        href: "/areas",
        action: "Open Areas",
        complete?: area_count > 0
      },
      %{
        id: "scenes",
        title: "Create a scene",
        description: "Build and activate the first useful area scene.",
        href: "/areas",
        action: "Open Areas",
        complete?: scene_count > 0
      }
    ]
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
