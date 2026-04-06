defmodule HueworksWeb.LightsLive.Editor do
  @moduledoc false

  alias Hueworks.Groups
  alias Hueworks.Lights
  alias HueworksWeb.LightsLive.Entities
  alias Hueworks.Util

  def default_assigns do
    %{
      edit_modal_open: false,
      edit_target_type: nil,
      edit_target_id: nil,
      edit_name: nil,
      edit_display_name: "",
      edit_show_link_selector: false,
      edit_canonical_light_id: nil,
      edit_link_targets: [],
      edit_room_id: nil,
      edit_actual_min_kelvin: "",
      edit_actual_max_kelvin: "",
      edit_extended_min_kelvin: "",
      edit_reported_min_kelvin: "",
      edit_reported_max_kelvin: "",
      edit_enabled: true,
      edit_mapping_supported: false,
      edit_extended_kelvin_range: false
    }
  end

  def open_assigns(type, id) do
    with {:ok, target} <- fetch_target(type, id) do
      {:ok,
       default_assigns()
       |> Map.merge(%{
         edit_modal_open: true,
         edit_target_type: type,
         edit_target_id: target.id,
         edit_name: Util.display_name(target),
         edit_display_name: target.display_name || "",
         edit_show_link_selector: type == "light" and not is_nil(target.canonical_light_id),
         edit_canonical_light_id: canonical_light_id_for(type, target),
         edit_link_targets: link_targets(type, target),
         edit_room_id: target.room_id,
         edit_actual_min_kelvin: Util.format_integer(target.actual_min_kelvin),
         edit_actual_max_kelvin: Util.format_integer(target.actual_max_kelvin),
         edit_extended_min_kelvin: Util.format_integer(target.extended_min_kelvin || 2000),
         edit_reported_min_kelvin: Util.format_integer(target.reported_min_kelvin),
         edit_reported_max_kelvin: Util.format_integer(target.reported_max_kelvin),
         edit_enabled: target.enabled,
         edit_mapping_supported: Hueworks.Kelvin.mapping_supported?(target),
         edit_extended_kelvin_range: target.extended_kelvin_range
       })}
    end
  end

  def update_assigns(assigns, params) do
    %{
      edit_display_name: Map.get(params, "display_name", assigns.edit_display_name),
      edit_canonical_light_id:
        Util.parse_optional_integer(
          Map.get(params, "canonical_light_id", assigns.edit_canonical_light_id)
        ),
      edit_actual_min_kelvin:
        Map.get(params, "actual_min_kelvin", assigns.edit_actual_min_kelvin),
      edit_actual_max_kelvin:
        Map.get(params, "actual_max_kelvin", assigns.edit_actual_max_kelvin),
      edit_extended_min_kelvin:
        Map.get(params, "extended_min_kelvin", assigns.edit_extended_min_kelvin),
      edit_room_id: Util.parse_optional_integer(Map.get(params, "room_id", assigns.edit_room_id)),
      edit_enabled: Util.parse_optional_bool(Map.get(params, "enabled", assigns.edit_enabled)),
      edit_extended_kelvin_range:
        Util.parse_optional_bool(
          Map.get(params, "extended_kelvin_range", assigns.edit_extended_kelvin_range)
        )
    }
  end

  def save(type, id, params) do
    attrs = normalize_attrs(params)

    with {:ok, target} <- Entities.fetch(type, id),
         {:ok, updated} <- apply_update(type, target, attrs) do
      {:ok, updated}
    end
  end

  defp fetch_target(type, id), do: Entities.fetch(type, id)

  defp apply_update("light", light, attrs), do: Lights.update_display_name(light, attrs)
  defp apply_update("group", group, attrs), do: Groups.update_display_name(group, attrs)
  defp apply_update(_type, _target, _attrs), do: {:error, :invalid_type}

  defp link_targets("light", light), do: Lights.list_link_targets(light)
  defp link_targets(_type, _target), do: []

  defp canonical_light_id_for("light", light), do: light.canonical_light_id
  defp canonical_light_id_for(_type, _target), do: nil

  defp normalize_attrs(params) do
    room_id =
      if Map.has_key?(params, "room_id") do
        Util.parse_optional_integer(Map.get(params, "room_id"))
      else
        :skip
      end

    [
      display_name: Map.get(params, "display_name"),
      canonical_light_id:
        if Map.has_key?(params, "canonical_light_id") do
          Util.parse_optional_integer(Map.get(params, "canonical_light_id"))
        else
          :skip
        end,
      room_id: room_id,
      actual_min_kelvin: Util.parse_optional_integer(Map.get(params, "actual_min_kelvin")),
      actual_max_kelvin: Util.parse_optional_integer(Map.get(params, "actual_max_kelvin")),
      extended_min_kelvin: Util.parse_optional_integer(Map.get(params, "extended_min_kelvin")),
      extended_kelvin_range: Util.parse_optional_bool(Map.get(params, "extended_kelvin_range")),
      enabled: Util.parse_optional_bool(Map.get(params, "enabled"))
    ]
    |> Enum.reject(fn
      {_key, :skip} -> true
      {:room_id, _} -> false
      {:canonical_light_id, _} -> false
      {_key, value} -> is_nil(value)
    end)
    |> Map.new()
  end
end
