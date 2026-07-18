defmodule HueworksWeb.PicoConfigLive.BindingEditor do
  @moduledoc false

  alias Hueworks.Util

  def update_assigns(assigns, params) when is_map(assigns) and is_map(params) do
    action = params["action"] || assigns[:binding_action]
    previous_target_kind = assigns[:binding_target_kind]
    binding_target_kind = normalize_target_kind(action)

    %{
      binding_target_kind: binding_target_kind,
      binding_target_id:
        normalize_target_id(
          binding_target_kind,
          params["target_id"] || assigns[:binding_target_id]
        ),
      binding_target_group_ids:
        normalize_target_group_ids_from_params(
          previous_target_kind,
          binding_target_kind,
          assigns[:control_groups] || [],
          params,
          assigns[:binding_target_group_ids] || []
        ),
      binding_action: normalize_action(action)
    }
  end

  def current_binding(assigns) when is_map(assigns) do
    %{
      "action" => assigns[:binding_action],
      "target_kind" => assigns[:binding_target_kind],
      "target_id" => assigns[:binding_target_id],
      "target_ids" => assigns[:binding_target_group_ids]
    }
  end

  def valid_learning_binding?(
        %{"action" => action, "target_kind" => "control_groups", "target_ids" => target_ids},
        control_groups,
        _area_scenes
      )
      when action in ["on", "off", "toggle"] and is_list(target_ids) do
    available_group_ids = MapSet.new(Enum.map(control_groups, & &1["id"]))
    target_ids != [] and Enum.all?(target_ids, &MapSet.member?(available_group_ids, &1))
  end

  def valid_learning_binding?(
        %{"action" => "activate_scene", "target_kind" => "scene", "target_id" => target_id},
        _control_groups,
        area_scenes
      )
      when is_integer(target_id) do
    Enum.any?(area_scenes, &(&1.id == target_id))
  end

  def valid_learning_binding?(_binding, _control_groups, _area_scenes), do: false

  def normalize_target_kind("activate_scene"), do: "scene"
  def normalize_target_kind(_action), do: "control_groups"

  def normalize_target_id("scene", target_id), do: Util.parse_optional_integer(target_id)
  def normalize_target_id("control_groups", _target_id), do: nil
  def normalize_target_id(_kind, _target_id), do: nil

  def normalize_action("activate_scene"), do: "activate_scene"

  def normalize_action(action) when action in ["on", "off", "toggle"], do: action
  def normalize_action(_action), do: "toggle"

  def normalize_target_group_ids(control_groups, target_ids) when is_list(control_groups) do
    valid_group_ids = MapSet.new(Enum.map(control_groups, & &1["id"]))

    target_ids
    |> List.wrap()
    |> Enum.filter(&is_binary/1)
    |> Enum.uniq()
    |> Enum.filter(&MapSet.member?(valid_group_ids, &1))
  end

  defp normalize_target_group_ids_from_params(
         _previous_target_kind,
         "scene",
         control_groups,
         _params,
         existing_ids
       ) do
    normalize_target_group_ids(control_groups, existing_ids)
  end

  defp normalize_target_group_ids_from_params(
         "scene",
         "control_groups",
         control_groups,
         params,
         existing_ids
       ) do
    target_ids = Map.get(params, "target_ids", existing_ids)
    normalize_target_group_ids(control_groups, target_ids)
  end

  defp normalize_target_group_ids_from_params(
         _previous_target_kind,
         "control_groups",
         control_groups,
         params,
         _existing_ids
       ) do
    target_ids = Map.get(params, "target_ids", [])
    normalize_target_group_ids(control_groups, target_ids)
  end

  defp normalize_target_group_ids_from_params(
         _previous_target_kind,
         _kind,
         _control_groups,
         _params,
         _existing_ids
       ),
       do: []
end
