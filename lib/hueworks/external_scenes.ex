defmodule Hueworks.ExternalScenes do
  @moduledoc """
  Syncs external scene definitions and resolves external triggers to HueWorks scenes.
  """

  import Ecto.Query, only: [from: 2]

  alias Hueworks.Import.Fetch.HomeAssistant
  alias Hueworks.Repo
  alias Hueworks.Scenes
  alias Hueworks.Schemas.{Bridge, ExternalScene, ExternalSceneMapping, Scene}

  def list_external_scenes_for_bridge(bridge_id) when is_integer(bridge_id) do
    Repo.all(
      from(es in ExternalScene,
        where: es.bridge_id == ^bridge_id,
        order_by: [asc: es.name],
        preload: [mapping: [:scene]]
      )
    )
  end

  def get_external_scene(id) when is_integer(id) do
    ExternalScene
    |> Repo.get(id)
    |> case do
      nil -> nil
      scene -> Repo.preload(scene, [:bridge, mapping: [:scene]])
    end
  end

  def list_mappable_scenes do
    Repo.all(
      from(s in Scene,
        order_by: [asc: s.room_id, asc: s.name],
        preload: [:room]
      )
    )
  end

  def sync_home_assistant_scenes(%Bridge{type: :ha} = bridge) do
    scenes = HomeAssistant.fetch_scene_entities_for_bridge(bridge)
    sync_home_assistant_scenes(bridge, scenes)
  rescue
    error -> {:error, Exception.message(error)}
  end

  def sync_home_assistant_scenes(%Bridge{id: bridge_id}, scene_entities) when is_list(scene_entities) do
    Repo.transaction(fn ->
      existing =
        Repo.all(from(es in ExternalScene, where: es.bridge_id == ^bridge_id and es.source == :ha))
        |> Map.new(&{&1.source_id, &1})

      seen_ids =
        Enum.reduce(scene_entities, MapSet.new(), fn entity, seen ->
          source_id = entity["source_id"] || entity[:source_id]

          if is_binary(source_id) and source_id != "" do
            attrs = normalize_scene_entity_attrs(bridge_id, entity)
            upsert_external_scene(existing[source_id], attrs)
            MapSet.put(seen, source_id)
          else
            seen
          end
        end)

      Enum.each(existing, fn {source_id, external_scene} ->
        if MapSet.member?(seen_ids, source_id) do
          :ok
        else
          external_scene
          |> ExternalScene.changeset(%{enabled: false})
          |> Repo.update!()
        end
      end)
    end)

    {:ok, list_external_scenes_for_bridge(bridge_id)}
  end

  def update_mapping(%ExternalScene{} = external_scene, attrs) when is_map(attrs) do
    mapping = Repo.get_by(ExternalSceneMapping, external_scene_id: external_scene.id) || %ExternalSceneMapping{}

    attrs =
      attrs
      |> Map.put("external_scene_id", external_scene.id)
      |> normalize_mapping_attrs()

    mapping
    |> ExternalSceneMapping.changeset(attrs)
    |> Repo.insert_or_update()
  end

  def activate_home_assistant_scene(bridge_id, source_id, opts \\ [])
      when is_integer(bridge_id) and is_binary(source_id) do
    with %ExternalScene{} = external_scene <-
           Repo.one(
             from(es in ExternalScene,
               where:
                 es.bridge_id == ^bridge_id and es.source == :ha and es.source_id == ^source_id and
                   es.enabled == true,
               preload: [mapping: [:scene]]
             )
           ),
         %ExternalSceneMapping{enabled: true, scene_id: scene_id} <- external_scene.mapping do
      Scenes.activate_scene(scene_id, opts)
    else
      nil -> :ignored
      _ -> :ignored
    end
  end

  def activate_home_assistant_scenes(bridge_id, source_ids, opts \\ [])
      when is_integer(bridge_id) and is_list(source_ids) do
    source_ids
    |> Enum.map(&to_string/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.uniq()
    |> Enum.reduce([], fn source_id, acc ->
      case activate_home_assistant_scene(bridge_id, source_id, opts) do
        {:ok, _diff, _updated} -> [source_id | acc]
        _ -> acc
      end
    end)
    |> Enum.reverse()
  end

  defp normalize_scene_entity_attrs(bridge_id, entity) do
    source_id = entity["source_id"] || entity[:source_id]
    name = entity["name"] || entity[:name] || source_id
    display_name = entity["display_name"] || entity[:display_name]
    metadata = entity["metadata"] || entity[:metadata] || %{}

    %{
      bridge_id: bridge_id,
      source: :ha,
      source_id: source_id,
      name: name,
      display_name: display_name,
      enabled: true,
      metadata: metadata
    }
  end

  defp upsert_external_scene(nil, attrs) do
    %ExternalScene{}
    |> ExternalScene.changeset(attrs)
    |> Repo.insert!()
  end

  defp upsert_external_scene(%ExternalScene{} = external_scene, attrs) do
    external_scene
    |> ExternalScene.changeset(attrs)
    |> Repo.update!()
  end

  defp normalize_mapping_attrs(attrs) do
    scene_id =
      case Map.get(attrs, "scene_id") || Map.get(attrs, :scene_id) do
        "" -> nil
        value when is_integer(value) -> value
        value when is_binary(value) ->
          case Integer.parse(value) do
            {parsed, ""} -> parsed
            _ -> nil
          end

        _ -> nil
      end

    enabled =
      case Map.get(attrs, "enabled") || Map.get(attrs, :enabled) do
        false -> false
        "false" -> false
        "off" -> false
        "0" -> false
        _ -> true
      end

    %{
      external_scene_id: Map.get(attrs, "external_scene_id") || Map.get(attrs, :external_scene_id),
      scene_id: scene_id,
      enabled: enabled,
      metadata: Map.get(attrs, "metadata") || Map.get(attrs, :metadata) || %{}
    }
  end
end
