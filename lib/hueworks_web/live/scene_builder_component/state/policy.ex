defmodule HueworksWeb.SceneBuilderComponent.State.Policy do
  @moduledoc false

  alias Hueworks.Scenes.Builder
  alias Hueworks.Scenes.PowerPolicy
  alias Hueworks.Util
  alias HueworksWeb.SceneBuilderComponent.Component

  def toggle_light_default_power(components, component_id, light_id) do
    component_id = Util.parse_id(component_id)
    light_id = Util.parse_id(light_id)

    Enum.map(components, fn component ->
      component = Component.new(component)

      if component.id == component_id and is_integer(light_id) do
        current =
          component
          |> light_default_power(light_id)
          |> PowerPolicy.parse()

        put_light_power_policy(component, light_id, PowerPolicy.cycle(current), [])
      else
        component
      end
    end)
  end

  def set_light_default_power(components, component_id, light_id, policy, presence_inputs) do
    component_id = Util.parse_id(component_id)
    light_id = Util.parse_id(light_id)
    policy = PowerPolicy.parse(policy)

    Enum.map(components, fn component ->
      component = Component.new(component)

      if component.id == component_id and is_integer(light_id) do
        put_light_power_policy(component, light_id, policy, presence_inputs)
      else
        component
      end
    end)
  end

  def set_light_presence_input(
        components,
        component_id,
        light_id,
        presence_input_id,
        presence_inputs
      ) do
    component_id = Util.parse_id(component_id)
    light_id = Util.parse_id(light_id)
    presence_input_id = valid_presence_input_id(presence_input_id, presence_inputs)

    Enum.map(components, fn component ->
      component = Component.new(component)

      if component.id == component_id and is_integer(light_id) and is_integer(presence_input_id) do
        %{
          component
          | light_defaults: Map.put(component.light_defaults, light_id, :follow_presence),
            light_presence_inputs:
              Map.put(component.light_presence_inputs, light_id, presence_input_id)
        }
      else
        component
      end
    end)
  end

  def toggle_group_default_power(components, component_id, group, area_light_ids) do
    component_id = Util.parse_id(component_id)

    Enum.map(components, fn component ->
      component = Component.new(component)

      if component.id == component_id and group do
        group_light_ids = component_group_light_ids(component, group, area_light_ids)
        current = group_default_power(component, group, area_light_ids)
        next = PowerPolicy.cycle(current)

        updated_defaults =
          group_light_ids
          |> Enum.reduce(component.light_defaults, fn light_id, acc ->
            Map.put(acc, light_id, next)
          end)

        %{component | light_defaults: updated_defaults}
      else
        component
      end
    end)
  end

  def set_group_default_power(
        components,
        component_id,
        group,
        area_light_ids,
        policy,
        presence_inputs
      ) do
    component_id = Util.parse_id(component_id)
    policy = PowerPolicy.parse(policy)

    Enum.map(components, fn component ->
      component = Component.new(component)

      if component.id == component_id and group do
        component
        |> component_group_light_ids(group, area_light_ids)
        |> Enum.reduce(component, fn light_id, acc ->
          put_light_power_policy(acc, light_id, policy, presence_inputs)
        end)
      else
        component
      end
    end)
  end

  def set_group_presence_input(
        components,
        component_id,
        group,
        area_light_ids,
        presence_input_id,
        presence_inputs
      ) do
    component_id = Util.parse_id(component_id)
    presence_input_id = valid_presence_input_id(presence_input_id, presence_inputs)

    Enum.map(components, fn component ->
      component = Component.new(component)

      if component.id == component_id and is_map(group) and is_integer(presence_input_id) do
        group_light_ids = component_group_light_ids(component, group, area_light_ids)

        updated_defaults =
          Enum.reduce(group_light_ids, component.light_defaults, fn light_id, acc ->
            Map.put(acc, light_id, :follow_presence)
          end)

        updated_presence_defaults =
          Enum.reduce(group_light_ids, component.light_presence_inputs, fn light_id, acc ->
            Map.put(acc, light_id, presence_input_id)
          end)

        %{
          component
          | light_defaults: updated_defaults,
            light_presence_inputs: updated_presence_defaults
        }
      else
        component
      end
    end)
  end

  def light_default_power(component, light_id) do
    component = Component.new(component)

    component.light_defaults
    |> Map.get(light_id, :default_on)
    |> PowerPolicy.parse()
  end

  def light_presence_input_id(component, light_id) do
    component
    |> Component.new()
    |> Map.get(:light_presence_inputs)
    |> Map.get(light_id)
    |> Util.parse_id()
  end

  def component_group_light_ids(component, group, area_light_ids) do
    component_light_ids =
      component
      |> Component.new()
      |> Map.get(:light_ids)
      |> MapSet.new()

    group
    |> Builder.group_area_light_ids(area_light_ids)
    |> Enum.filter(&MapSet.member?(component_light_ids, &1))
  end

  def group_default_power(component, group, area_light_ids) do
    group_light_ids = component_group_light_ids(component, group, area_light_ids)

    policies =
      group_light_ids
      |> Enum.map(&light_default_power(component, &1))
      |> Enum.uniq()

    presence_input_ids =
      group_light_ids
      |> Enum.map(&light_presence_input_id(component, &1))
      |> Enum.uniq()

    case {policies, presence_input_ids} do
      {[:follow_presence], [_presence_input_id]} -> :follow_presence
      {[policy], _presence_input_ids} when policy != :follow_presence -> policy
      _ -> :mixed
    end
  end

  def group_presence_input_id(component, group, area_light_ids) do
    component
    |> component_group_light_ids(group, area_light_ids)
    |> Enum.map(&light_presence_input_id(component, &1))
    |> Enum.uniq()
    |> case do
      [presence_input_id] -> presence_input_id
      _ -> nil
    end
  end

  defp put_light_power_policy(component, light_id, :follow_presence, presence_inputs) do
    presence_input_id =
      component
      |> light_presence_input_id(light_id)
      |> case do
        id when is_integer(id) -> id
        _ -> first_presence_input_id(presence_inputs)
      end

    if is_integer(presence_input_id) do
      %{
        component
        | light_defaults: Map.put(component.light_defaults, light_id, :follow_presence),
          light_presence_inputs:
            Map.put(component.light_presence_inputs, light_id, presence_input_id)
      }
    else
      put_light_power_policy(component, light_id, :default_on, [])
    end
  end

  defp put_light_power_policy(component, light_id, policy, _presence_inputs) do
    %{
      component
      | light_defaults: Map.put(component.light_defaults, light_id, policy),
        light_presence_inputs: Map.delete(component.light_presence_inputs, light_id)
    }
  end

  defp valid_presence_input_id(presence_input_id, presence_inputs) do
    presence_input_id = Util.parse_id(presence_input_id)
    valid_ids = valid_presence_input_ids(presence_inputs)

    if MapSet.member?(valid_ids, presence_input_id), do: presence_input_id, else: nil
  end

  defp valid_presence_input_ids(presence_inputs) do
    presence_inputs
    |> List.wrap()
    |> Enum.map(&Map.get(&1, :id))
    |> Enum.filter(&is_integer/1)
    |> MapSet.new()
  end

  defp first_presence_input_id(presence_inputs) do
    presence_inputs
    |> List.wrap()
    |> Enum.find_value(&Map.get(&1, :id))
  end
end
