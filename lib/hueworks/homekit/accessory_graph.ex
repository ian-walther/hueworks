defmodule Hueworks.HomeKit.AccessoryGraph do
  @moduledoc false

  alias Hueworks.AppSettings
  alias Hueworks.HomeKit.{Config, Entities, ValueStore}
  alias Hueworks.Util

  def build do
    config =
      AppSettings.get_global()
      |> Config.from_settings()

    lights = Entities.list_exposed_lights()
    groups = Entities.list_exposed_groups()
    scenes = if config.scenes_enabled, do: Entities.list_scenes(), else: []

    topology = topology(config, lights, groups, scenes)

    if topology_empty?(topology) do
      {:disabled, topology}
    else
      {:ok, accessory_server(config, lights, groups, scenes), topology}
    end
  end

  def topology_hash(topology) when is_map(topology) do
    topology
    |> :erlang.term_to_binary()
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.encode16(case: :lower)
  end

  defp accessory_server(config, lights, groups, scenes) do
    %HAP.AccessoryServer{
      name: config.bridge_name,
      model: Config.model(),
      identifier: config.identifier,
      pairing_code: config.pairing_code,
      setup_id: config.setup_id,
      data_path: config.data_path,
      accessory_type: Config.accessory_type_bridge(),
      accessories: accessories(lights, groups, scenes)
    }
  end

  defp accessories(lights, groups, scenes) do
    Enum.map(lights, &light_accessory/1) ++
      Enum.map(groups, &group_accessory/1) ++
      Enum.map(scenes, &scene_accessory/1)
  end

  defp light_accessory(light) do
    accessory("HueWorks Light", "light-#{light.id}", display_name(light), [
      %HAP.Services.LightBulb{
        name: display_name(light),
        on: {ValueStore, kind: :light, id: light.id}
      }
    ])
  end

  defp group_accessory(group) do
    accessory("HueWorks Group", "group-#{group.id}", display_name(group), [
      %HAP.Services.LightBulb{
        name: display_name(group),
        on: {ValueStore, kind: :group, id: group.id}
      }
    ])
  end

  defp scene_accessory(scene) do
    accessory("HueWorks Scene", "scene-#{scene.id}", display_name(scene), [
      %HAP.Services.Switch{
        name: display_name(scene),
        on: {ValueStore, kind: :scene, id: scene.id}
      }
    ])
  end

  defp accessory(model, serial_number, name, services) do
    %HAP.Accessory{
      name: name,
      model: model,
      manufacturer: "HueWorks",
      serial_number: serial_number,
      firmware_revision: Application.spec(:hueworks, :vsn) |> to_string(),
      services: services
    }
  end

  defp topology(config, lights, groups, scenes) do
    %{
      bridge_name: config.bridge_name,
      data_path: config.data_path,
      identifier: config.identifier,
      scenes_enabled: config.scenes_enabled,
      lights: Enum.map(lights, &entity_topology/1),
      groups: Enum.map(groups, &entity_topology/1),
      scenes: Enum.map(scenes, &scene_topology/1)
    }
  end

  defp entity_topology(entity) do
    %{
      id: entity.id,
      name: display_name(entity),
      mode: entity.homekit_export_mode,
      room_id: entity.room_id
    }
  end

  defp scene_topology(scene) do
    %{
      id: scene.id,
      name: display_name(scene),
      room_id: scene.room_id
    }
  end

  defp topology_empty?(%{lights: [], groups: [], scenes: []}), do: true
  defp topology_empty?(_topology), do: false

  defp display_name(entity), do: Util.display_name(entity)
end
