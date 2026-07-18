defmodule HueworksWeb.SceneBuilderComponent.Component do
  @moduledoc false

  alias Hueworks.Scenes.PowerPolicy
  alias Hueworks.Schemas.LightState
  alias Hueworks.Util
  alias HueworksWeb.LightStateEditorLive.FormState

  @fields [
    :id,
    :name,
    :light_ids,
    :group_ids,
    :light_state_id,
    :embedded_manual_config,
    :light_defaults,
    :light_presence_inputs
  ]

  defstruct id: 1,
            name: "Component 1",
            light_ids: [],
            group_ids: [],
            light_state_id: nil,
            embedded_manual_config: nil,
            light_defaults: %{},
            light_presence_inputs: %{}

  def new(attrs \\ %{}) do
    attrs = known_attrs(attrs)

    %__MODULE__{}
    |> struct(attrs)
    |> normalize_shape()
  end

  def from_saved(component) do
    light_defaults =
      component.scene_component_lights
      |> Enum.reduce(%{}, fn join, acc ->
        Map.put(acc, join.light_id, join.default_power)
      end)

    light_presence_inputs =
      component.scene_component_lights
      |> Enum.reduce(%{}, fn join, acc ->
        if join.presence_input_id do
          Map.put(acc, join.light_id, join.presence_input_id)
        else
          acc
        end
      end)

    new(%{
      id: component.id,
      name: component.name || "Component",
      light_ids: Enum.map(component.lights, & &1.id),
      group_ids: [],
      light_state_id: if(component.light_state_id, do: to_string(component.light_state_id)),
      embedded_manual_config: component.embedded_manual_config,
      light_defaults: light_defaults,
      light_presence_inputs: light_presence_inputs
    })
  end

  def normalize(component, light_states, presence_inputs \\ []) do
    %__MODULE__{} = component = new(component)

    valid_state_ids =
      light_states
      |> List.wrap()
      |> Enum.map(& &1.id)
      |> Enum.map(&to_string/1)
      |> MapSet.new()

    light_ids = normalize_id_list(component.light_ids)
    group_ids = normalize_id_list(component.group_ids)

    defaults =
      component.light_defaults
      |> keep_defaults_for_light_ids(light_ids)
      |> ensure_defaults_for_light_ids(light_ids)

    presence_defaults =
      component.light_presence_inputs
      |> normalize_presence_inputs_map(presence_inputs)
      |> keep_defaults_for_light_ids(light_ids)
      |> keep_presence_inputs_for_following_lights(defaults)

    light_state_id = normalize_saved_light_state_id(component.light_state_id, valid_state_ids)

    %__MODULE__{
      component
      | light_ids: light_ids,
        group_ids: group_ids,
        light_defaults: defaults,
        light_presence_inputs: presence_defaults,
        light_state_id: light_state_id,
        embedded_manual_config:
          normalize_embedded_manual_config(component.embedded_manual_config, light_state_id)
    }
  end

  def normalize_saved_light_state_id(nil, _valid_ids), do: nil
  def normalize_saved_light_state_id("", _valid_ids), do: nil

  def normalize_saved_light_state_id(state_id, valid_ids) do
    state_id = to_string(state_id)

    if MapSet.size(valid_ids) == 0 or MapSet.member?(valid_ids, state_id), do: state_id, else: nil
  end

  def embedded_manual_config?(component) do
    component
    |> new()
    |> Map.get(:embedded_manual_config)
    |> case do
      config when is_map(config) -> map_size(config) > 0
      _ -> false
    end
  end

  def default_custom_config(config, :color) do
    config
    |> FormState.manual_default_edits()
    |> Map.put("mode", "color")
    |> put_default_when_blank("brightness", "100")
    |> put_default_when_blank("hue", "0")
    |> put_default_when_blank("saturation", "100")
    |> Map.take(["mode", "brightness", "hue", "saturation"])
  end

  def default_custom_config(config, _mode) do
    config
    |> FormState.manual_default_edits()
    |> Map.put("mode", "temperature")
    |> put_default_when_blank("brightness", "100")
    |> put_default_when_blank("temperature", "3000")
    |> Map.take(["mode", "brightness", "temperature"])
  end

  defp put_default_when_blank(config, key, default) do
    case Map.get(config, key) do
      value when is_binary(value) ->
        if String.trim(value) == "", do: Map.put(config, key, default), else: config

      nil ->
        Map.put(config, key, default)

      _value ->
        config
    end
  end

  defp known_attrs(%__MODULE__{} = component), do: Map.from_struct(component)

  defp known_attrs(attrs) when is_list(attrs) do
    attrs
    |> Map.new()
    |> known_attrs()
  end

  defp known_attrs(attrs) when is_map(attrs) do
    @fields
    |> Enum.reduce(%{}, fn field, acc ->
      value = Map.get(attrs, field, Map.get(attrs, to_string(field), :__missing__))

      case value do
        :__missing__ -> acc
        _ -> Map.put(acc, field, value)
      end
    end)
  end

  defp known_attrs(_attrs), do: %{}

  defp normalize_shape(%__MODULE__{} = component) do
    id = Util.parse_id(component.id) || 1

    %__MODULE__{
      component
      | id: id,
        name: normalize_name(component.name, id),
        light_ids: normalize_id_list(component.light_ids),
        group_ids: normalize_id_list(component.group_ids),
        light_defaults: normalize_light_defaults_map(component.light_defaults),
        light_presence_inputs: normalize_id_map(component.light_presence_inputs)
    }
  end

  defp normalize_name(name, _id) when is_binary(name) and name != "", do: name
  defp normalize_name(_name, id), do: "Component #{id}"

  defp normalize_id_list(values) do
    values
    |> List.wrap()
    |> Enum.map(&Util.parse_id/1)
    |> Enum.filter(&is_integer/1)
    |> Enum.uniq()
  end

  defp normalize_light_defaults_map(defaults) when is_map(defaults) do
    defaults
    |> Enum.reduce(%{}, fn {key, value}, acc ->
      case Util.parse_id(key) do
        nil -> acc
        light_id -> Map.put(acc, light_id, PowerPolicy.parse(value))
      end
    end)
  end

  defp normalize_light_defaults_map(_defaults), do: %{}

  defp normalize_id_map(values) when is_map(values) do
    values
    |> Enum.reduce(%{}, fn {key, value}, acc ->
      with light_id when is_integer(light_id) <- Util.parse_id(key),
           input_id when is_integer(input_id) <- Util.parse_id(value) do
        Map.put(acc, light_id, input_id)
      else
        _ -> acc
      end
    end)
  end

  defp normalize_id_map(_values), do: %{}

  defp normalize_presence_inputs_map(presence_inputs, valid_presence_inputs)
       when is_map(presence_inputs) do
    valid_ids = valid_presence_input_ids(valid_presence_inputs)

    presence_inputs
    |> Enum.reduce(%{}, fn {key, value}, acc ->
      with light_id when is_integer(light_id) <- Util.parse_id(key),
           input_id when is_integer(input_id) <- Util.parse_id(value),
           true <- MapSet.member?(valid_ids, input_id) do
        Map.put(acc, light_id, input_id)
      else
        _ -> acc
      end
    end)
  end

  defp normalize_presence_inputs_map(_presence_inputs, _valid_presence_inputs), do: %{}

  defp valid_presence_input_ids(presence_inputs) do
    presence_inputs
    |> List.wrap()
    |> Enum.map(&Map.get(&1, :id))
    |> Enum.filter(&is_integer/1)
    |> MapSet.new()
  end

  defp keep_defaults_for_light_ids(defaults, light_ids) do
    allowed_ids = MapSet.new(light_ids)

    defaults
    |> Enum.filter(fn {light_id, _} -> MapSet.member?(allowed_ids, light_id) end)
    |> Map.new()
  end

  defp ensure_defaults_for_light_ids(defaults, light_ids) do
    light_ids
    |> Enum.reduce(defaults, fn light_id, acc ->
      Map.put_new(acc, light_id, :default_on)
    end)
  end

  defp keep_presence_inputs_for_following_lights(presence_inputs, defaults) do
    presence_inputs
    |> Enum.filter(fn {light_id, _presence_input_id} ->
      Map.get(defaults, light_id) == :follow_presence
    end)
    |> Map.new()
  end

  defp normalize_embedded_manual_config(embedded_manual_config, light_state_id) do
    if normalize_saved_light_state_id(light_state_id, MapSet.new()) do
      nil
    else
      case embedded_manual_config do
        config when is_map(config) and map_size(config) > 0 ->
          default_custom_config(config, LightState.manual_mode(config))

        _ ->
          nil
      end
    end
  end
end
