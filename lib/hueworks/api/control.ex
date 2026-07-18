defmodule Hueworks.Api.Control do
  @moduledoc false

  alias Hueworks.ActiveScenes
  alias Hueworks.Color
  alias Hueworks.Control.{State, TraceBuffer}
  alias Hueworks.ControlTargets
  alias Hueworks.Groups
  alias Hueworks.Kelvin
  alias Hueworks.Lights.ManualControl
  alias Hueworks.Repo
  alias Hueworks.Scenes
  alias Hueworks.Schemas.{Group, Light, Area, Scene}

  @type kind :: :light | :group

  def control_entity(kind, id, command) when kind in [:light, :group] and is_integer(id) do
    with {:ok, target} <- fetch_target(kind, id),
         {:ok, control} <- normalize_control(target.entity, command),
         {:ok, _result} <- dispatch(target, control) do
      {:ok,
       %{
         operation: "#{kind}_control",
         target: %{kind: Atom.to_string(kind), id: id},
         accepted_intent: control.accepted_intent,
         trace_id: target.trace.trace_id,
         plan: plan_summary(target.trace.trace_id)
       }}
    end
  end

  def control_entity(_kind, _id, _command), do: {:error, :not_found}

  def activate_scene(scene_id) when is_integer(scene_id) do
    case Scenes.get_scene(scene_id) do
      nil ->
        {:error, :not_found}

      %Scene{} = scene ->
        trace = trace("api.scene_activate", scene.area_id, scene.id)

        TraceBuffer.record(trace, :intent, %{
          entity_kind: :scene,
          entity_id: scene.id,
          action_count: 0
        })

        case Scenes.activate_scene(scene.id, trace: trace) do
          {:ok, plan_diff, _updated} ->
            {:ok,
             %{
               operation: "scene_activate",
               target: %{kind: "scene", id: scene.id},
               accepted_intent: %{"active" => true},
               intended_light_count: map_size(plan_diff),
               trace_id: trace.trace_id,
               plan: plan_summary(trace.trace_id)
             }}

          other ->
            other
        end
    end
  end

  def activate_scene(_scene_id), do: {:error, :not_found}

  def deactivate_area_scene(area_id) when is_integer(area_id) do
    case Repo.get(Area, area_id) do
      nil ->
        {:error, :not_found}

      %Area{} ->
        trace = trace("api.area_scene_deactivate", area_id)

        TraceBuffer.record(trace, :intent, %{
          entity_kind: :area,
          entity_id: area_id,
          action_count: 0
        })

        :ok = ActiveScenes.clear_for_area(area_id)

        {:ok,
         %{
           operation: "area_scene_deactivate",
           target: %{kind: "area", id: area_id},
           accepted_intent: %{"active_scene" => false},
           trace_id: trace.trace_id,
           plan: %{action_count: 0, bridge_count: 0}
         }}
    end
  end

  def deactivate_area_scene(_area_id), do: {:error, :not_found}

  def refresh_physical_state do
    trace = trace("api.physical_state_refresh", nil)

    TraceBuffer.record(trace, :intent, %{action_count: 0})

    :ok = State.refresh()

    {:ok,
     %{
       operation: "physical_state_refresh",
       target: nil,
       accepted_intent: %{},
       trace_id: trace.trace_id,
       plan: %{action_count: 0, bridge_count: 0}
     }}
  end

  defp fetch_target(:light, light_id) do
    case ControlTargets.fetch_entity(:light, light_id) do
      %Light{enabled: true, area_id: area_id} = light when is_integer(area_id) ->
        {:ok,
         %{
           entity: light,
           area_id: area_id,
           light_ids: [light.id],
           trace: trace("api.light_control", area_id)
         }}

      _ ->
        {:error, :not_found}
    end
  end

  defp fetch_target(:group, group_id) do
    case ControlTargets.fetch_entity(:group, group_id) do
      %Group{enabled: true, area_id: area_id} = group when is_integer(area_id) ->
        case Groups.member_light_ids(group.id) do
          [] ->
            {:error, :no_members}

          light_ids ->
            {:ok,
             %{
               entity: group,
               area_id: area_id,
               light_ids: light_ids,
               trace: trace("api.group_control", area_id)
             }}
        end

      _ ->
        {:error, :not_found}
    end
  end

  defp normalize_control(entity, command) when is_map(command) do
    case Map.keys(command) do
      ["power"] -> normalize_power(Map.get(command, "power"))
      ["brightness"] -> normalize_brightness(Map.get(command, "brightness"))
      ["kelvin"] -> normalize_kelvin(entity, Map.get(command, "kelvin"))
      ["color"] -> normalize_color(entity, Map.get(command, "color"))
      _ -> {:error, :invalid_control}
    end
  end

  defp normalize_control(_entity, _command), do: {:error, :invalid_control}

  defp normalize_power("on") do
    {:ok, %{kind: :power, power: :on, accepted_intent: %{"power" => "on"}}}
  end

  defp normalize_power("off") do
    {:ok, %{kind: :power, power: :off, accepted_intent: %{"power" => "off"}}}
  end

  defp normalize_power(_power), do: {:error, :invalid_control}

  defp normalize_brightness(value) when is_integer(value) and value in 1..100 do
    {:ok,
     %{
       kind: :manual,
       desired: %{brightness: value},
       accepted_intent: %{"brightness" => value}
     }}
  end

  defp normalize_brightness(_value), do: {:error, :invalid_control}

  defp normalize_kelvin(%{supports_temp: true} = entity, value) when is_integer(value) do
    {min_kelvin, max_kelvin} = Kelvin.derive_range(entity)

    if value in min_kelvin..max_kelvin do
      {:ok,
       %{
         kind: :manual,
         desired: %{kelvin: value},
         accepted_intent: %{"kelvin" => value}
       }}
    else
      {:error, :invalid_control}
    end
  end

  defp normalize_kelvin(%{supports_temp: false}, _value), do: {:error, :unsupported_capability}
  defp normalize_kelvin(_entity, _value), do: {:error, :invalid_control}

  defp normalize_color(%{supports_color: false}, _value), do: {:error, :unsupported_capability}

  defp normalize_color(%{supports_color: true}, %{"hue" => hue, "saturation" => saturation})
       when is_integer(hue) and hue in 0..360 and is_integer(saturation) and saturation in 0..100 do
    case Color.hs_to_xy(hue, saturation) do
      {x, y} when is_number(x) and is_number(y) ->
        {:ok,
         %{
           kind: :manual,
           desired: %{power: :on, x: x, y: y},
           accepted_intent: %{"color" => %{"hue" => hue, "saturation" => saturation}}
         }}

      _ ->
        {:error, :invalid_control}
    end
  end

  defp normalize_color(%{supports_color: true}, _value), do: {:error, :invalid_control}
  defp normalize_color(_entity, _value), do: {:error, :invalid_control}

  defp dispatch(target, %{kind: :power, power: power}) do
    ManualControl.apply_power_action(target.area_id, target.light_ids, power, trace: target.trace)
  end

  defp dispatch(target, %{kind: :manual, desired: desired}) do
    ManualControl.apply_updates(target.area_id, target.light_ids, desired, trace: target.trace)
  end

  defp plan_summary(trace_id) do
    TraceBuffer.trace_summary(trace_id)
  end

  defp trace(source, area_id, scene_id \\ nil) do
    sequence = System.unique_integer([:positive])

    %{
      trace_id: "api-#{sequence}",
      source: source,
      area_id: area_id,
      trace_area_id: area_id,
      scene_id: scene_id,
      trace_scene_id: scene_id,
      started_at_ms: System.monotonic_time(:millisecond)
    }
  end
end
