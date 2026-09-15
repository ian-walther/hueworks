defmodule Hueworks.HomeKit.AccessoryGraph do
  @moduledoc false

  alias Hueworks.AppSettings
  alias Hueworks.HomeKit.{AccessoryIds, Config, Entities, LightBulbService, ValueStore}
  alias Hueworks.Util

  def build do
    config =
      AppSettings.get_global()
      |> Config.from_settings()

    lights = Entities.list_exposed_lights()
    groups = Entities.list_exposed_groups()
    scenes = if config.scenes_enabled, do: Entities.list_scenes(), else: []

    serial_numbers =
      Enum.map(lights, &serial_number(:light, &1.id)) ++
        Enum.map(groups, &serial_number(:group, &1.id)) ++
        Enum.map(scenes, &serial_number(:scene, &1.id))

    ids = AccessoryIds.assign(serial_numbers, reserve_bridge?: not paired?(config))
    iids = AccessoryIds.instance_ids(lightbulb_types(lights, groups))
    live = live_accessories(lights, groups, scenes, ids, iids)
    accessories = with_primary(live, config, ids)
    topology = topology(config, lights, groups, scenes, ids, accessories)

    if topology_empty?(topology) do
      {:disabled, topology}
    else
      {:ok, accessory_server(config, accessories), topology}
    end
  end

  @doc "Whether an accessory is the bridge itself rather than an exported entity."
  def primary?(%HAP.Accessory{model: model}), do: model == Config.model()

  @doc """
  The accessory server to publish until pairing completes: the bridge accessory alone at
  ID 1, whatever the full graph looks like. On a fresh install that is the reserved bridge
  accessory; on an upgraded install, whose first entity normally holds ID 1, a bridge
  accessory is built for the shell and the entity returns to ID 1 once paired.
  """
  def pairing_shell(%HAP.AccessoryServer{} = accessory_server) do
    primary =
      Enum.find(accessory_server.accessories, &primary?/1) ||
        bridge_accessory(accessory_server.name, accessory_server.identifier, 1)

    %{accessory_server | accessories: [primary]}
  end

  # HAP requires accessory ID 1 to represent the bridge. A fresh install reserved it, so
  # the bridge accessory is always published there. An install upgraded from positional
  # numbering has its first entity at 1; the bridge accessory fills that slot only while
  # the entity is not exposed, so a primary accessory always exists and the entity's own
  # ID is untouched when it returns.
  defp with_primary(live, config, ids) do
    case Map.get(ids, AccessoryIds.bridge_serial_number()) do
      nil ->
        if Enum.any?(live, &(&1.aid == 1)) do
          live
        else
          Enum.sort_by(
            [bridge_accessory(config.bridge_name, config.identifier, 1) | live],
            & &1.aid
          )
        end

      bridge_aid ->
        Enum.sort_by(
          [bridge_accessory(config.bridge_name, config.identifier, bridge_aid) | live],
          & &1.aid
        )
    end
  end

  defp bridge_accessory(name, identifier, aid) do
    %HAP.Accessory{
      aid: aid,
      name: name,
      model: Config.model(),
      manufacturer: "HueWorks",
      serial_number: identifier,
      firmware_revision: Application.spec(:hueworks, :vsn) |> to_string(),
      services: []
    }
  end

  defp paired?(config) do
    Application.get_env(:hueworks, :homekit_pairing_state_module, Hueworks.HomeKit.PairingState).paired?(
      config.data_path
    )
  end

  def serial_number(:light, id), do: "light-#{id}"
  def serial_number(:group, id), do: "group-#{id}"
  def serial_number(:scene, id), do: "scene-#{id}"

  def topology_hash(topology) when is_map(topology) do
    topology
    |> :erlang.term_to_binary()
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.encode16(case: :lower)
  end

  defp accessory_server(config, accessories) do
    %HAP.AccessoryServer{
      name: config.bridge_name,
      model: Config.model(),
      identifier: config.identifier,
      pairing_code: config.pairing_code,
      setup_id: config.setup_id,
      data_path: config.data_path,
      accessory_type: Config.accessory_type_bridge(),
      accessories: accessories
    }
  end

  # Every accessory carries its persisted ID, so list order no longer matters to HomeKit;
  # the list is sorted by ID for a stable tree. New IDs are handed out in lights, groups,
  # scenes order (each by name), matching the positional order used before IDs were
  # persisted, so an existing install keeps every accessory where it was.
  defp live_accessories(lights, groups, scenes, ids, iids) do
    (Enum.map(lights, &light_accessory(&1, ids, iids)) ++
       Enum.map(groups, &group_accessory(&1, ids, iids)) ++
       Enum.map(scenes, &scene_accessory(&1, ids)))
    |> Enum.sort_by(& &1.aid)
  end

  defp lightbulb_types(lights, groups) do
    Map.new(
      Enum.map(lights, &{serial_number(:light, &1.id), lightbulb_service(:light, &1)}) ++
        Enum.map(groups, &{serial_number(:group, &1.id), lightbulb_service(:group, &1)}),
      fn {serial_number, service} -> {serial_number, LightBulbService.present_types(service)} end
    )
  end

  defp light_accessory(light, ids, iids) do
    serial_number = serial_number(:light, light.id)

    accessory("HueWorks Light", serial_number, display_name(light), ids, [
      %{lightbulb_service(:light, light) | iids: Map.fetch!(iids, serial_number)}
    ])
  end

  defp group_accessory(group, ids, iids) do
    serial_number = serial_number(:group, group.id)

    accessory("HueWorks Group", serial_number, display_name(group), ids, [
      %{lightbulb_service(:group, group) | iids: Map.fetch!(iids, serial_number)}
    ])
  end

  # Switch mode publishes On only. Light mode adds Brightness, plus Hue and Saturation
  # when the entity supports color and Color Temperature when it supports temperature.
  defp lightbulb_service(kind, entity) do
    value_opts = [kind: kind, id: entity.id]
    light? = entity.homekit_export_mode == :light
    color? = light? and entity.supports_color == true
    temp? = light? and entity.supports_temp == true

    %LightBulbService{
      name: display_name(entity),
      on: source(value_opts, :on),
      brightness: if(light?, do: source(value_opts, :brightness)),
      hue: if(color?, do: source(value_opts, :hue)),
      saturation: if(color?, do: source(value_opts, :saturation)),
      color_temperature: if(temp?, do: source(value_opts, :color_temperature))
    }
  end

  defp source(value_opts, characteristic) do
    {ValueStore, Keyword.put(value_opts, :characteristic, characteristic)}
  end

  defp scene_accessory(scene, ids) do
    accessory("HueWorks Scene", serial_number(:scene, scene.id), display_name(scene), ids, [
      %HAP.Services.Switch{
        name: display_name(scene),
        on: {ValueStore, kind: :scene, id: scene.id}
      }
    ])
  end

  defp accessory(model, serial_number, name, ids, services) do
    %HAP.Accessory{
      aid: Map.fetch!(ids, serial_number),
      name: name,
      model: model,
      manufacturer: "HueWorks",
      serial_number: serial_number,
      firmware_revision: Application.spec(:hueworks, :vsn) |> to_string(),
      services: services
    }
  end

  defp topology(config, lights, groups, scenes, ids, accessories) do
    %{
      bridge_name: config.bridge_name,
      primary_aid: accessories |> Enum.find(&primary?/1) |> then(&(&1 && &1.aid)),
      data_path: config.data_path,
      identifier: config.identifier,
      scenes_enabled: config.scenes_enabled,
      lights: Enum.map(lights, &entity_topology(:light, &1, ids)),
      groups: Enum.map(groups, &entity_topology(:group, &1, ids)),
      scenes: Enum.map(scenes, &scene_topology(&1, ids))
    }
  end

  defp entity_topology(kind, entity, ids) do
    %{
      id: entity.id,
      aid: Map.fetch!(ids, serial_number(kind, entity.id)),
      name: display_name(entity),
      mode: entity.homekit_export_mode,
      supports_color: entity.supports_color == true,
      supports_temp: entity.supports_temp == true,
      area_id: entity.area_id
    }
  end

  defp scene_topology(scene, ids) do
    %{
      id: scene.id,
      aid: Map.fetch!(ids, serial_number(:scene, scene.id)),
      name: display_name(scene),
      area_id: scene.area_id
    }
  end

  defp topology_empty?(%{lights: [], groups: [], scenes: []}), do: true
  defp topology_empty?(_topology), do: false

  defp display_name(entity), do: Util.display_name(entity)
end
