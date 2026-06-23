defmodule HueworksWeb.SceneBuilderComponent.Flow do
  @moduledoc false

  alias Hueworks.Scenes.Builder
  alias Hueworks.Util
  alias HueworksWeb.SceneBuilderComponent.State

  def initialize(assigns) do
    components =
      State.normalize_components(
        assigns.components,
        assigns.light_states,
        Map.get(assigns, :presence_inputs, [])
      )

    %{
      components: components,
      builder: build_builder(assigns, components)
    }
  end

  def add_component(assigns) do
    assigns.components
    |> State.add_component()
    |> component_change(assigns)
  end

  def select_light(assigns, component_id, light_id) do
    assigns.components
    |> State.add_light(component_id, Util.parse_id(light_id))
    |> component_change(assigns)
  end

  def select_group(assigns, component_id, group_id) do
    group = Enum.find(assigns.groups, &(&1.id == Util.parse_id(group_id)))

    assigns.components
    |> State.add_group(component_id, group, assigns.builder.room_light_ids)
    |> component_change(assigns)
  end

  def select_light_state(assigns, component_id, state_id) do
    assigns.components
    |> State.select_light_state(component_id, state_id, assigns.light_states)
    |> component_change(assigns)
  end

  def update_embedded_manual_config(assigns, component_id, params) do
    assigns.components
    |> State.update_embedded_manual_config(component_id, params)
    |> component_change(assigns)
  end

  def remove_light(assigns, component_id, light_id) do
    assigns.components
    |> State.remove_light(component_id, light_id)
    |> component_change(assigns)
  end

  def remove_group(assigns, component_id, group_id) do
    group = Enum.find(assigns.groups, &(&1.id == Util.parse_id(group_id)))

    assigns.components
    |> State.remove_group(component_id, group, assigns.builder.room_light_ids)
    |> component_change(assigns)
  end

  def remove_component(assigns, component_id) do
    assigns.components
    |> State.remove_component(component_id)
    |> component_change(assigns)
  end

  def toggle_light_default_power(assigns, component_id, light_id) do
    assigns.components
    |> State.toggle_light_default_power(component_id, light_id)
    |> component_change(assigns)
  end

  def toggle_group_default_power(assigns, component_id, group_id) do
    group = Enum.find(assigns.groups, &(&1.id == Util.parse_id(group_id)))

    assigns.components
    |> State.toggle_group_default_power(component_id, group, assigns.builder.room_light_ids)
    |> component_change(assigns)
  end

  def set_light_default_power(assigns, component_id, light_id, policy) do
    assigns.components
    |> State.set_light_default_power(
      component_id,
      light_id,
      policy,
      Map.get(assigns, :presence_inputs, [])
    )
    |> component_change(assigns)
  end

  def set_light_presence_input(assigns, component_id, light_id, presence_input_id) do
    assigns.components
    |> State.set_light_presence_input(
      component_id,
      light_id,
      presence_input_id,
      Map.get(assigns, :presence_inputs, [])
    )
    |> component_change(assigns)
  end

  def set_group_default_power(assigns, component_id, group_id, policy) do
    group = Enum.find(assigns.groups, &(&1.id == Util.parse_id(group_id)))

    assigns.components
    |> State.set_group_default_power(
      component_id,
      group,
      assigns.builder.room_light_ids,
      policy,
      Map.get(assigns, :presence_inputs, [])
    )
    |> component_change(assigns)
  end

  def set_group_presence_input(assigns, component_id, group_id, presence_input_id) do
    group = Enum.find(assigns.groups, &(&1.id == Util.parse_id(group_id)))

    assigns.components
    |> State.set_group_presence_input(
      component_id,
      group,
      assigns.builder.room_light_ids,
      presence_input_id,
      Map.get(assigns, :presence_inputs, [])
    )
    |> component_change(assigns)
  end

  defp component_change(components, assigns) do
    %{
      components: components,
      builder: build_builder(assigns, components)
    }
  end

  defp build_builder(assigns, components) do
    assigns.room_lights
    |> List.wrap()
    |> then(&Builder.build(&1, List.wrap(assigns.groups), List.wrap(components)))
  end
end
