defmodule HueworksWeb.SceneBuilderComponent.State.CustomState do
  @moduledoc false

  alias Hueworks.Schemas.LightState
  alias Hueworks.Util
  alias HueworksWeb.LightStateEditorLive.FormState
  alias HueworksWeb.SceneBuilderComponent.Component

  def select_light_state(components, component_id, state_id, light_states) do
    valid_ids =
      light_states
      |> List.wrap()
      |> Enum.map(& &1.id)
      |> Enum.map(&to_string/1)
      |> MapSet.new()

    component_id = Util.parse_id(component_id)

    Enum.map(components, fn component ->
      component = Component.new(component)

      if component.id == component_id do
        normalize_component_light_state_selection(component, state_id, valid_ids)
      else
        component
      end
    end)
  end

  def update_embedded_manual_config(components, component_id, params) when is_map(params) do
    component_id = Util.parse_id(component_id)

    Enum.map(components, fn component ->
      component = Component.new(component)

      if component.id == component_id do
        mode =
          case Map.get(params, "mode") do
            "color" -> :color
            _ -> :temperature
          end

        current_config =
          component
          |> Map.get(:embedded_manual_config)
          |> Component.default_custom_config(mode)

        {_name, config} = FormState.merge_form_params(:manual, "", current_config, params)

        %{
          component
          | light_state_id: nil,
            embedded_manual_config: Component.default_custom_config(config, mode)
        }
      else
        component
      end
    end)
  end

  def selected_state_id(%{light_state_id: light_state_id}), do: Util.parse_id(light_state_id)
  def selected_state_id(_component), do: nil

  def selected_state_value(component) when is_map(component) do
    component = Component.new(component)

    cond do
      state_id = component.light_state_id ->
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
    component = Component.new(component)

    Component.embedded_manual_config?(component) and
      LightState.manual_mode(component.embedded_manual_config) != :color
  end

  def custom_manual?(_component), do: false

  def custom_color?(component) when is_map(component) do
    component = Component.new(component)

    Component.embedded_manual_config?(component) and
      LightState.manual_mode(component.embedded_manual_config) == :color
  end

  def custom_color?(_component), do: false

  def custom_field_value(component, key) when is_map(component) do
    component
    |> Component.new()
    |> Map.get(:embedded_manual_config)
    |> Component.default_custom_config(
      if(custom_color?(component), do: :color, else: :temperature)
    )
    |> FormState.manual_field_value(key)
  end

  def custom_color_preview_style(component),
    do: component |> custom_config(:color) |> FormState.manual_color_preview_style()

  def custom_color_preview_label(component),
    do: component |> custom_config(:color) |> FormState.manual_color_preview_label()

  def custom_saturation_scale_style(component),
    do: component |> custom_config(:color) |> FormState.manual_saturation_scale_style()

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
          | light_state_id: Component.normalize_saved_light_state_id(state_id, valid_ids),
            embedded_manual_config: nil
        }
    end
  end

  defp custom_config(component, mode) do
    component
    |> Component.new()
    |> Map.get(:embedded_manual_config)
    |> Component.default_custom_config(mode)
  end
end
