defmodule HueworksWeb.SceneBuilderComponent.State.Membership do
  @moduledoc false

  alias Hueworks.Scenes.Builder
  alias Hueworks.Util
  alias HueworksWeb.SceneBuilderComponent.Component

  def blank_component, do: Component.new()

  def add_component(components) do
    components = normalize_components(components)

    next_id =
      components
      |> Enum.map(& &1.id)
      |> Enum.max(fn -> 0 end)
      |> Kernel.+(1)

    components ++ [Component.new(id: next_id, name: "Component #{next_id}")]
  end

  def add_light(components, component_id, light_id) do
    component_id = Util.parse_id(component_id)

    Enum.map(components, fn component ->
      component = Component.new(component)

      if component.id == component_id and is_integer(light_id) do
        %{
          component
          | light_ids: Enum.uniq(component.light_ids ++ [light_id]),
            light_defaults: Map.put(component.light_defaults, light_id, :default_on),
            light_presence_inputs: Map.delete(component.light_presence_inputs, light_id)
        }
      else
        component
      end
    end)
  end

  def add_group(components, component_id, group, area_light_ids) do
    component_id = Util.parse_id(component_id)

    Enum.map(components, fn component ->
      component = Component.new(component)

      if component.id == component_id and group do
        group_light_ids = Builder.group_area_light_ids(group, area_light_ids)

        defaults =
          group_light_ids
          |> Enum.reduce(component.light_defaults, fn light_id, acc ->
            Map.put_new(acc, light_id, :default_on)
          end)

        %{
          component
          | light_ids: Enum.uniq(component.light_ids ++ group_light_ids),
            group_ids: Enum.uniq(component.group_ids ++ [group.id]),
            light_defaults: defaults,
            light_presence_inputs: Map.drop(component.light_presence_inputs, group_light_ids)
        }
      else
        component
      end
    end)
  end

  def remove_light(components, component_id, light_id) do
    component_id = Util.parse_id(component_id)
    light_id = Util.parse_id(light_id)

    Enum.map(components, fn component ->
      component = Component.new(component)

      if component.id == component_id do
        %{
          component
          | light_ids: List.delete(component.light_ids, light_id),
            light_defaults: Map.delete(component.light_defaults, light_id),
            light_presence_inputs: Map.delete(component.light_presence_inputs, light_id)
        }
      else
        component
      end
    end)
  end

  def remove_group(components, component_id, group, area_light_ids) do
    component_id = Util.parse_id(component_id)

    Enum.map(components, fn component ->
      component = Component.new(component)

      if component.id == component_id and group do
        group_light_ids = Builder.group_area_light_ids(group, area_light_ids)

        %{
          component
          | light_ids: Enum.reject(component.light_ids, &(&1 in group_light_ids)),
            group_ids: List.delete(component.group_ids, group.id),
            light_defaults: Map.drop(component.light_defaults, group_light_ids),
            light_presence_inputs: Map.drop(component.light_presence_inputs, group_light_ids)
        }
      else
        component
      end
    end)
  end

  def remove_component(components, component_id) do
    components
    |> normalize_components()
    |> Enum.reject(&(&1.id == Util.parse_id(component_id)))
    |> case do
      [] -> [blank_component()]
      remaining -> remaining
    end
  end

  defp normalize_components(components), do: Enum.map(List.wrap(components), &Component.new/1)
end
