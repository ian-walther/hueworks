defmodule HueworksWeb.SceneBuilderComponent.State do
  @moduledoc false

  alias Hueworks.Scenes.Builder
  alias Hueworks.Schemas.LightState
  alias Hueworks.Util

  @blank_component %{
    id: 1,
    name: "Component 1",
    light_ids: [],
    group_ids: [],
    light_state_id: nil,
    light_defaults: %{}
  }

  def blank_component, do: @blank_component

  def add_component(components) do
    next_id =
      components
      |> Enum.map(& &1.id)
      |> Enum.max(fn -> 0 end)
      |> Kernel.+(1)

    components ++
      [Map.put(@blank_component, :id, next_id) |> Map.put(:name, "Component #{next_id}")]
  end

  def select_light(selections, component_id, light_id) do
    Map.put(selections || %{}, {:light, parse_id(component_id)}, parse_id(light_id))
  end

  def select_group(selections, component_id, group_id) do
    Map.put(selections || %{}, {:group, parse_id(component_id)}, parse_id(group_id))
  end

  def select_light_state(components, component_id, state_id, light_states) do
    valid_ids =
      light_states
      |> Enum.map(& &1.id)
      |> Enum.map(&to_string/1)
      |> MapSet.new()

    component_id = parse_id(component_id)
    normalized_state_id = normalize_light_state_id(state_id, valid_ids)

    Enum.map(components, fn component ->
      if component.id == component_id do
        %{component | light_state_id: normalized_state_id}
      else
        component
      end
    end)
  end

  def add_light(components, component_id, light_id) do
    component_id = parse_id(component_id)

    Enum.map(components, fn component ->
      if component.id == component_id and is_integer(light_id) do
        defaults =
          component
          |> Map.get(:light_defaults, %{})
          |> Map.put(light_id, :force_on)

        %{
          component
          | light_ids: Enum.uniq(component.light_ids ++ [light_id]),
            light_defaults: defaults
        }
      else
        component
      end
    end)
  end

  def add_group(components, component_id, group, room_light_ids) do
    component_id = parse_id(component_id)

    Enum.map(components, fn component ->
      if component.id == component_id and group do
        group_light_ids = Builder.group_room_light_ids(group, room_light_ids)

        defaults =
          group_light_ids
          |> Enum.reduce(Map.get(component, :light_defaults, %{}), fn light_id, acc ->
            Map.put_new(acc, light_id, :force_on)
          end)

        %{
          component
          | light_ids: Enum.uniq(component.light_ids ++ group_light_ids),
            group_ids: Enum.uniq(component.group_ids ++ [group.id]),
            light_defaults: defaults
        }
      else
        component
      end
    end)
  end

  def remove_light(components, component_id, light_id) do
    component_id = parse_id(component_id)
    light_id = parse_id(light_id)

    Enum.map(components, fn component ->
      if component.id == component_id do
        defaults =
          component
          |> Map.get(:light_defaults, %{})
          |> Map.delete(light_id)

        %{
          component
          | light_ids: List.delete(component.light_ids, light_id),
            light_defaults: defaults
        }
      else
        component
      end
    end)
  end

  def remove_component(components, component_id) do
    components
    |> Enum.reject(&(&1.id == parse_id(component_id)))
    |> case do
      [] -> [@blank_component]
      remaining -> remaining
    end
  end

  def toggle_light_default_power(components, component_id, light_id) do
    component_id = parse_id(component_id)
    light_id = parse_id(light_id)

    Enum.map(components, fn component ->
      if component.id == component_id and is_integer(light_id) do
        defaults = Map.get(component, :light_defaults, %{})

        current =
          defaults
          |> Map.get(light_id, :force_on)
          |> normalize_default_power_value()

        %{component | light_defaults: Map.put(defaults, light_id, next_power_policy(current))}
      else
        component
      end
    end)
  end

  def toggle_group_default_power(components, component_id, group, room_light_ids) do
    component_id = parse_id(component_id)

    Enum.map(components, fn component ->
      if component.id == component_id and group do
        group_light_ids = component_group_light_ids(component, group, room_light_ids)
        current = group_default_power(component, group, room_light_ids)
        next = next_power_policy(current)
        defaults = Map.get(component, :light_defaults, %{})

        updated_defaults =
          group_light_ids
          |> Enum.reduce(defaults, fn light_id, acc ->
            Map.put(acc, light_id, next)
          end)

        %{component | light_defaults: updated_defaults}
      else
        component
      end
    end)
  end

  def normalize_components(components, light_states) do
    valid_ids =
      light_states
      |> Enum.map(& &1.id)
      |> Enum.map(&to_string/1)
      |> MapSet.new()

    Enum.map(components, fn component ->
      light_ids = Map.get(component, :light_ids, [])

      defaults =
        component
        |> Map.get(:light_defaults, %{})
        |> normalize_light_defaults_map()
        |> keep_defaults_for_light_ids(light_ids)
        |> ensure_defaults_for_light_ids(light_ids)

      component
      |> Map.put(:light_defaults, defaults)
      |> Map.put(
        :light_state_id,
        normalize_light_state_id(Map.get(component, :light_state_id), valid_ids)
      )
    end)
  end

  def light_default_power(component, light_id) do
    component
    |> Map.get(:light_defaults, %{})
    |> Map.get(light_id, :force_on)
    |> normalize_default_power_value()
  end

  def component_groups(component, groups, room_light_ids) do
    component_light_ids = MapSet.new(Map.get(component, :light_ids, []))

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

  def component_group_light_ids(component, group, room_light_ids) do
    component_light_ids = MapSet.new(Map.get(component, :light_ids, []))

    group
    |> Builder.group_room_light_ids(room_light_ids)
    |> Enum.filter(&MapSet.member?(component_light_ids, &1))
  end

  def group_default_power(component, group, room_light_ids) do
    component
    |> component_group_light_ids(group, room_light_ids)
    |> Enum.map(&light_default_power(component, &1))
    |> Enum.uniq()
    |> case do
      [policy] -> policy
      _ -> :mixed
    end
  end

  def power_policy_label(:force_on), do: "Default On"
  def power_policy_label(:force_off), do: "Default Off"
  def power_policy_label(:follow_occupancy), do: "Follow Occupancy"
  def power_policy_label(:mixed), do: "..."

  def selected_state_id(%{light_state_id: light_state_id}), do: parse_id(light_state_id)
  def selected_state_id(_component), do: nil

  def state_option_label(%{type: :circadian, name: name}), do: "#{name} (circadian)"

  def state_option_label(%{type: :manual, name: name, config: config}) do
    suffix =
      case LightState.manual_mode(config) do
        :color -> "manual color"
        _ -> "manual temp"
      end

    "#{name} (#{suffix})"
  end

  def state_option_label(%{name: name}), do: name

  def display_name(entity), do: Util.display_name(entity)

  def light_name(lights, id) do
    lights
    |> Enum.find(&(&1.id == id))
    |> case do
      nil -> "Light #{id}"
      light -> display_name(light)
    end
  end

  defp normalize_light_state_id(nil, _valid_ids), do: nil
  defp normalize_light_state_id("", _valid_ids), do: nil

  defp normalize_light_state_id(state_id, valid_ids) do
    state_id = to_string(state_id)

    if MapSet.member?(valid_ids, state_id), do: state_id, else: nil
  end

  defp parse_id(value), do: Util.parse_id(value)

  defp normalize_light_defaults_map(defaults) when is_map(defaults) do
    defaults
    |> Enum.reduce(%{}, fn {key, value}, acc ->
      case parse_id(key) do
        nil -> acc
        light_id -> Map.put(acc, light_id, normalize_default_power_value(value))
      end
    end)
  end

  defp normalize_light_defaults_map(_defaults), do: %{}

  defp keep_defaults_for_light_ids(defaults, light_ids) do
    allowed_ids = MapSet.new(light_ids)

    defaults
    |> Enum.filter(fn {light_id, _} -> MapSet.member?(allowed_ids, light_id) end)
    |> Map.new()
  end

  defp ensure_defaults_for_light_ids(defaults, light_ids) do
    light_ids
    |> Enum.reduce(defaults, fn light_id, acc ->
      Map.put_new(acc, light_id, :force_on)
    end)
  end

  defp normalize_default_power_value(value) when value in [:force_on, "force_on"], do: :force_on

  defp normalize_default_power_value(value) when value in [:force_off, "force_off"],
    do: :force_off

  defp normalize_default_power_value(value) when value in [:follow_occupancy, "follow_occupancy"],
    do: :follow_occupancy

  defp normalize_default_power_value(value) when value in [true, "true", 1, "1", :on, "on"],
    do: :force_on

  defp normalize_default_power_value(value) when value in [false, "false", 0, "0", :off, "off"],
    do: :force_off

  defp normalize_default_power_value(_value), do: :force_on

  defp next_power_policy(:force_on), do: :force_off
  defp next_power_policy(:force_off), do: :follow_occupancy
  defp next_power_policy(:follow_occupancy), do: :force_on
  defp next_power_policy(:mixed), do: :force_on
  defp next_power_policy(_policy), do: :force_on
end
