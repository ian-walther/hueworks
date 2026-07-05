defmodule Hueworks.Import.DestructiveReview do
  @moduledoc false

  import Ecto.Query, only: [from: 2]

  alias Hueworks.Import.ReviewPlan
  alias Hueworks.Repo

  alias Hueworks.Schemas.{
    Bridge,
    Group,
    GroupLight,
    Light,
    Scene,
    SceneComponent,
    SceneComponentLight
  }

  def summarize(%Bridge{} = bridge, plan) do
    entries = ReviewPlan.destructive_resolutions(plan)
    lights = fetch_lights(bridge.id, entries)
    groups = fetch_groups(bridge.id, entries)
    light_dependencies = light_dependencies(lights)
    group_dependencies = group_dependencies(groups)

    entries
    |> Enum.flat_map(fn entry ->
      case entry.type do
        :light ->
          summarize_entity(entry, Map.get(lights, entry.source_id), light_dependencies)

        :group ->
          summarize_entity(entry, Map.get(groups, entry.source_id), group_dependencies)
      end
    end)
  end

  defp summarize_entity(_entry, nil, _dependencies), do: []

  defp summarize_entity(entry, entity, dependencies) do
    [
      %{
        type: entry.type,
        source_id: entry.source_id,
        action: entry.action,
        action_label: action_label(entry.action),
        type_label: type_label(entry.type),
        name: display_name(entity.display_name, entity.name),
        dependents: Map.get(dependencies, entry.source_id, [])
      }
    ]
  end

  defp fetch_lights(bridge_id, entries) do
    source_ids = source_ids(entries, :light)

    if source_ids == [] do
      %{}
    else
      Light
      |> by_bridge_source_ids(bridge_id, source_ids)
      |> Repo.all()
      |> Map.new(&{&1.source_id, &1})
    end
  end

  defp fetch_groups(bridge_id, entries) do
    source_ids = source_ids(entries, :group)

    if source_ids == [] do
      %{}
    else
      Group
      |> by_bridge_source_ids(bridge_id, source_ids)
      |> Repo.all()
      |> Map.new(&{&1.source_id, &1})
    end
  end

  defp by_bridge_source_ids(query, bridge_id, source_ids) do
    from(entity in query,
      where: entity.bridge_id == ^bridge_id and entity.source_id in ^source_ids
    )
  end

  defp light_dependencies(lights) when lights == %{}, do: %{}

  defp light_dependencies(lights) do
    lights_by_id =
      lights
      |> Map.values()
      |> Map.new(&{&1.id, &1.source_id})

    light_ids = Map.keys(lights_by_id)

    scene_dependents =
      Repo.all(
        from(scl in SceneComponentLight,
          join: sc in SceneComponent,
          on: sc.id == scl.scene_component_id,
          join: s in Scene,
          on: s.id == sc.scene_id,
          where: scl.light_id in ^light_ids,
          select: {scl.light_id, s.display_name, s.name, sc.name}
        )
      )
      |> Enum.map(fn {light_id, scene_display_name, scene_name, component_name} ->
        dependent =
          if is_binary(component_name) and component_name != "" do
            "Scene: #{display_name(scene_display_name, scene_name)} / #{component_name}"
          else
            "Scene: #{display_name(scene_display_name, scene_name)}"
          end

        {Map.fetch!(lights_by_id, light_id), dependent}
      end)

    group_dependents =
      Repo.all(
        from(gl in GroupLight,
          join: g in Group,
          on: g.id == gl.group_id,
          where: gl.light_id in ^light_ids,
          select: {gl.light_id, g.display_name, g.name}
        )
      )
      |> Enum.map(fn {light_id, group_display_name, group_name} ->
        {Map.fetch!(lights_by_id, light_id),
         "Group: #{display_name(group_display_name, group_name)}"}
      end)

    (scene_dependents ++ group_dependents)
    |> by_source_id()
  end

  defp group_dependencies(groups) when groups == %{}, do: %{}

  defp group_dependencies(groups) do
    groups_by_id =
      groups
      |> Map.values()
      |> Map.new(&{&1.id, &1.source_id})

    group_ids = Map.keys(groups_by_id)

    Repo.all(
      from(gl in GroupLight,
        join: l in Light,
        on: l.id == gl.light_id,
        where: gl.group_id in ^group_ids,
        select: {gl.group_id, l.display_name, l.name}
      )
    )
    |> Enum.map(fn {group_id, light_display_name, light_name} ->
      {Map.fetch!(groups_by_id, group_id),
       "Member light: #{display_name(light_display_name, light_name)}"}
    end)
    |> by_source_id()
  end

  defp by_source_id(dependencies) do
    dependencies
    |> Enum.group_by(fn {source_id, _dependent} -> source_id end, fn {_source_id, dependent} ->
      dependent
    end)
    |> Map.new(fn {source_id, values} -> {source_id, Enum.uniq(values)} end)
  end

  defp source_ids(entries, type) do
    entries
    |> Enum.filter(&(&1.type == type))
    |> Enum.map(& &1.source_id)
    |> Enum.uniq()
  end

  defp action_label(:delete), do: "Delete"
  defp action_label(:disable), do: "Disable"

  defp type_label(:light), do: "light"
  defp type_label(:group), do: "group"

  defp display_name(display_name, _name) when is_binary(display_name) and display_name != "",
    do: display_name

  defp display_name(_display_name, name) when is_binary(name) and name != "", do: name
  defp display_name(_display_name, _name), do: "Unknown"
end
