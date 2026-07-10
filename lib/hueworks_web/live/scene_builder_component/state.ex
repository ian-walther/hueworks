defmodule HueworksWeb.SceneBuilderComponent.State do
  @moduledoc false

  alias Hueworks.Groups.Topology
  alias Hueworks.Scenes.Builder
  alias Hueworks.Scenes.LightStates
  alias Hueworks.Scenes.PowerPolicy
  alias Hueworks.Util
  alias HueworksWeb.SceneBuilderComponent.Component
  alias HueworksWeb.SceneBuilderComponent.State.CustomState
  alias HueworksWeb.SceneBuilderComponent.State.Membership
  alias HueworksWeb.SceneBuilderComponent.State.Policy

  def blank_component, do: Membership.blank_component()
  def add_component(components), do: Membership.add_component(components)

  def add_light(components, component_id, light_id),
    do: Membership.add_light(components, component_id, light_id)

  def add_group(components, component_id, group, room_light_ids),
    do: Membership.add_group(components, component_id, group, room_light_ids)

  def remove_light(components, component_id, light_id),
    do: Membership.remove_light(components, component_id, light_id)

  def remove_group(components, component_id, group, room_light_ids),
    do: Membership.remove_group(components, component_id, group, room_light_ids)

  def remove_component(components, component_id),
    do: Membership.remove_component(components, component_id)

  def select_light_state(components, component_id, state_id, light_states),
    do: CustomState.select_light_state(components, component_id, state_id, light_states)

  def update_embedded_manual_config(components, component_id, params),
    do: CustomState.update_embedded_manual_config(components, component_id, params)

  def toggle_light_default_power(components, component_id, light_id),
    do: Policy.toggle_light_default_power(components, component_id, light_id)

  def set_light_default_power(components, component_id, light_id, policy, presence_inputs),
    do:
      Policy.set_light_default_power(components, component_id, light_id, policy, presence_inputs)

  def set_light_presence_input(
        components,
        component_id,
        light_id,
        presence_input_id,
        presence_inputs
      ),
      do:
        Policy.set_light_presence_input(
          components,
          component_id,
          light_id,
          presence_input_id,
          presence_inputs
        )

  def toggle_group_default_power(components, component_id, group, room_light_ids),
    do: Policy.toggle_group_default_power(components, component_id, group, room_light_ids)

  def set_group_default_power(
        components,
        component_id,
        group,
        room_light_ids,
        policy,
        presence_inputs
      ),
      do:
        Policy.set_group_default_power(
          components,
          component_id,
          group,
          room_light_ids,
          policy,
          presence_inputs
        )

  def set_group_presence_input(
        components,
        component_id,
        group,
        room_light_ids,
        presence_input_id,
        presence_inputs
      ),
      do:
        Policy.set_group_presence_input(
          components,
          component_id,
          group,
          room_light_ids,
          presence_input_id,
          presence_inputs
        )

  def normalize_components(components, light_states, presence_inputs \\ []) do
    components
    |> List.wrap()
    |> Enum.map(&Component.normalize(&1, light_states, presence_inputs))
  end

  def light_default_power(component, light_id),
    do: Policy.light_default_power(component, light_id)

  def light_presence_input_id(component, light_id),
    do: Policy.light_presence_input_id(component, light_id)

  def component_group_topology(component, groups, room_light_ids) do
    component = Component.new(component)

    groups
    |> Enum.map(fn group ->
      Map.put(group, :light_ids, Builder.group_room_light_ids(group, room_light_ids))
    end)
    |> Topology.presentation_tree(component.light_ids)
  end

  def component_groups(component, groups, room_light_ids) do
    component = Component.new(component)
    component_light_ids = MapSet.new(component.light_ids)

    groups
    |> Enum.filter(fn group ->
      group_light_ids = Builder.group_room_light_ids(group, room_light_ids)

      group_light_ids != [] and
        Enum.all?(group_light_ids, &MapSet.member?(component_light_ids, &1))
    end)
    |> Enum.sort_by(fn group ->
      {-Enum.count(component_group_light_ids(component, group, room_light_ids)),
       group |> display_name() |> String.downcase(), group.id}
    end)
  end

  def component_group_light_ids(component, group, room_light_ids),
    do: Policy.component_group_light_ids(component, group, room_light_ids)

  def group_default_power(component, group, room_light_ids),
    do: Policy.group_default_power(component, group, room_light_ids)

  def group_presence_input_id(component, group, room_light_ids),
    do: Policy.group_presence_input_id(component, group, room_light_ids)

  def power_policy_label(policy), do: PowerPolicy.label(policy)

  def selected_state_id(component), do: CustomState.selected_state_id(component)
  def selected_state_value(component), do: CustomState.selected_state_value(component)
  def custom_manual?(component), do: CustomState.custom_manual?(component)
  def custom_color?(component), do: CustomState.custom_color?(component)
  def custom_field_value(component, key), do: CustomState.custom_field_value(component, key)
  def custom_color_preview_style(component), do: CustomState.custom_color_preview_style(component)
  def custom_color_preview_label(component), do: CustomState.custom_color_preview_label(component)

  def custom_saturation_scale_style(component),
    do: CustomState.custom_saturation_scale_style(component)

  def state_option_label(state), do: LightStates.editor_label(state)

  def display_name(entity), do: Util.display_name(entity)

  def light_name(lights, id) do
    lights
    |> Enum.find(&(&1.id == id))
    |> case do
      nil -> "Light #{id}"
      light -> display_name(light)
    end
  end

  def presence_input_name(presence_inputs, id) do
    presence_inputs
    |> Enum.find(&(&1.id == id))
    |> case do
      nil -> "Presence Input #{id}"
      presence_input -> display_name(presence_input)
    end
  end
end
