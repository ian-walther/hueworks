defmodule HueworksWeb.LightsLive.FilterState do
  @moduledoc false

  alias HueworksWeb.FilterPrefs
  alias Hueworks.Util

  def param_updates(params) when is_map(params) do
    %{}
    |> maybe_put_param(:group_filter, params["group_filter"])
    |> maybe_put_param(:light_filter, params["light_filter"])
    |> maybe_put_param(:group_area_filter, params["group_area_filter"])
    |> maybe_put_param(:light_area_filter, params["light_area_filter"])
  end

  def event_updates("set_group_filter", %{"group_filter" => filter}, _areas) do
    %{group_filter: Util.parse_filter(filter)}
  end

  def event_updates("set_group_area_filter", %{"group_area_filter" => filter}, areas) do
    %{group_area_filter: normalize_area_filter(filter, areas)}
  end

  def event_updates("set_light_filter", %{"light_filter" => filter}, _areas) do
    %{light_filter: Util.parse_filter(filter)}
  end

  def event_updates("set_light_area_filter", %{"light_area_filter" => filter}, areas) do
    %{light_area_filter: normalize_area_filter(filter, areas)}
  end

  def event_updates("toggle_group_disabled", params, _areas) do
    %{show_disabled_groups: Map.get(params, "show_disabled_groups") == "true"}
  end

  def event_updates("toggle_light_disabled", params, _areas) do
    %{show_disabled_lights: Map.get(params, "show_disabled_lights") == "true"}
  end

  def event_updates("toggle_light_linked", params, _areas) do
    %{show_linked_lights: Map.get(params, "show_linked_lights") == "true"}
  end

  def store(assigns, updates) when is_map(assigns) do
    updates = Map.new(updates)

    if is_binary(assigns.filter_session_id) do
      FilterPrefs.update(assigns.filter_session_id, updates)
    end

    updates
  end

  defp normalize_area_filter(filter, areas) do
    filter
    |> Util.parse_area_filter()
    |> Util.normalize_area_filter(areas)
  end

  defp maybe_put_param(acc, _key, nil), do: acc
  defp maybe_put_param(acc, _key, ""), do: acc
  defp maybe_put_param(acc, key, value), do: Map.put(acc, key, value)
end
