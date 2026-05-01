defmodule HueworksWeb.SceneBuilderComponent.State do
  @moduledoc false

  alias Hueworks.Groups.Topology
  alias Hueworks.Scenes.Builder
  alias Hueworks.Schemas.LightState
  alias HueworksWeb.LightStateEditorLive.FormState
  alias Hueworks.Util

  @blank_component %{
    id: 1,
    name: "Component 1",
    light_ids: [],
    group_ids: [],
    light_state_id: nil,
    embedded_manual_config: nil,
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

  def select_light_state(components, component_id, state_id, light_states) do
    valid_ids =
      light_states
      |> Enum.map(& &1.id)
      |> Enum.map(&to_string/1)
      |> MapSet.new()

    component_id = parse_id(component_id)

    Enum.map(components, fn component ->
      if component.id == component_id do
        normalize_component_light_state_selection(component, state_id, valid_ids)
      else
        component
      end
    end)
  end

  def update_embedded_manual_config(components, component_id, params) when is_map(params) do
    component_id = parse_id(component_id)

    Enum.map(components, fn component ->
      if component.id == component_id do
        mode =
          case Map.get(params, "mode") do
            "color" -> :color
            _ -> :temperature
          end

        current_config =
          component
          |> Map.get(:embedded_manual_config)
          |> default_custom_config(mode)

        {_name, config} = FormState.merge_form_params(:manual, "", current_config, params)

        %{
          component
          | light_state_id: nil,
            embedded_manual_config: default_custom_config(config, mode)
        }
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

  def remove_group(components, component_id, group, room_light_ids) do
    component_id = parse_id(component_id)

    Enum.map(components, fn component ->
      if component.id == component_id and group do
        group_light_ids = Builder.group_room_light_ids(group, room_light_ids)
        light_ids = Map.get(component, :light_ids, [])

        remaining_light_ids =
          Enum.reject(light_ids, fn light_id -> light_id in group_light_ids end)

        remaining_defaults =
          component
          |> Map.get(:light_defaults, %{})
          |> Map.drop(group_light_ids)

        %{
          component
          | light_ids: remaining_light_ids,
            group_ids: List.delete(Map.get(component, :group_ids, []), group.id),
            light_defaults: remaining_defaults
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
        normalize_saved_light_state_id(Map.get(component, :light_state_id), valid_ids)
      )
      |> Map.put(
        :embedded_manual_config,
        normalize_embedded_manual_config(
          Map.get(component, :embedded_manual_config),
          Map.get(component, :light_state_id)
        )
      )
    end)
  end

  def light_default_power(component, light_id) do
    component
    |> Map.get(:light_defaults, %{})
    |> Map.get(light_id, :force_on)
    |> normalize_default_power_value()
  end

  def component_group_topology(component, groups, room_light_ids) do
    groups
    |> Enum.map(fn group ->
      Map.put(group, :light_ids, Builder.group_room_light_ids(group, room_light_ids))
    end)
    |> Topology.presentation_tree(Map.get(component, :light_ids, []))
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

  def selected_state_value(component) when is_map(component) do
    cond do
      state_id = Map.get(component, :light_state_id) ->
        to_string(state_id)

      custom_color?(component) ->
        "custom_color"

      custom_manual?(component) ->
        "custom"

      true ->
        nil
    end
  end

  def custom_manual?(component) when is_map(component) do
    embedded_manual_config?(component) and
      LightState.manual_mode(component.embedded_manual_config) != :color
  end

  def custom_manual?(_component), do: false

  def custom_color?(component) when is_map(component) do
    embedded_manual_config?(component) and
      LightState.manual_mode(component.embedded_manual_config) == :color
  end

  def custom_color?(_component), do: false

  def custom_field_value(component, key) when is_map(component) do
    component
    |> Map.get(:embedded_manual_config)
    |> default_custom_config(if(custom_color?(component), do: :color, else: :temperature))
    |> FormState.manual_field_value(key)
  end

  def custom_color_preview_style(component),
    do: component |> custom_config(:color) |> FormState.manual_color_preview_style()

  def custom_color_preview_label(component),
    do: component |> custom_config(:color) |> FormState.manual_color_preview_label()

  def custom_saturation_scale_style(component),
    do: component |> custom_config(:color) |> FormState.manual_saturation_scale_style()

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

  defp normalize_saved_light_state_id(nil, _valid_ids), do: nil
  defp normalize_saved_light_state_id("", _valid_ids), do: nil

  defp normalize_saved_light_state_id(state_id, valid_ids) do
    state_id = to_string(state_id)

    if MapSet.size(valid_ids) == 0 or MapSet.member?(valid_ids, state_id), do: state_id, else: nil
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

  defp normalize_component_light_state_selection(component, state_id, valid_ids) do
    case state_id do
      "custom" ->
        %{
          component
          | light_state_id: nil,
            embedded_manual_config: custom_config(component, :temperature)
        }

      "custom_color" ->
        %{
          component
          | light_state_id: nil,
            embedded_manual_config: custom_config(component, :color)
        }

      _ ->
        %{
          component
          | light_state_id: normalize_saved_light_state_id(state_id, valid_ids),
            embedded_manual_config: nil
        }
    end
  end

  defp normalize_embedded_manual_config(embedded_manual_config, light_state_id) do
    if normalize_saved_light_state_id(light_state_id, MapSet.new()) do
      nil
    else
      case embedded_manual_config do
        config when is_map(config) and map_size(config) > 0 ->
          config
          |> default_custom_config(LightState.manual_mode(config))

        _ ->
          nil
      end
    end
  end

  defp embedded_manual_config?(component) do
    component
    |> Map.get(:embedded_manual_config)
    |> case do
      config when is_map(config) -> map_size(config) > 0
      _ -> false
    end
  end

  defp custom_config(component, mode) do
    component
    |> Map.get(:embedded_manual_config)
    |> default_custom_config(mode)
  end

  defp default_custom_config(config, :color) do
    config
    |> FormState.manual_default_edits()
    |> Map.put("mode", "color")
    |> Map.put_new("brightness", "100")
    |> Map.put_new("hue", "0")
    |> Map.put_new("saturation", "100")
  end

  defp default_custom_config(config, _mode) do
    config
    |> FormState.manual_default_edits()
    |> Map.put("mode", "temperature")
    |> Map.put_new("brightness", "100")
    |> Map.put_new("temperature", "3000")
  end
end
