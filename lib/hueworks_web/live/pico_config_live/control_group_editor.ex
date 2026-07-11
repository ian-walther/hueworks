defmodule HueworksWeb.PicoConfigLive.ControlGroupEditor do
  @moduledoc false

  import Phoenix.Component, only: [assign: 2]

  alias Hueworks.Picos
  alias HueworksWeb.PicoConfigLive.Loader

  def load_selected(socket) do
    assign(socket, load_selected_assigns(socket.assigns))
  end

  def load_selected_assigns(assigns) when is_map(assigns) do
    selected_group =
      Enum.find(
        assigns[:control_groups] || [],
        &(&1["id"] == assigns[:selected_control_group_id])
      )

    %{
      editing_control_group_name: false,
      control_group_name: (selected_group && selected_group["name"]) || "",
      control_group_name_draft: (selected_group && selected_group["name"]) || "",
      control_group_group_ids: (selected_group && selected_group["group_ids"]) || [],
      control_group_light_ids: (selected_group && selected_group["light_ids"]) || [],
      selected_control_group_group_id: nil,
      selected_control_group_light_id: nil
    }
  end

  def select(socket, id) do
    socket
    |> assign(selected_control_group_id: to_string(id))
    |> load_selected()
  end

  def deselect(socket) do
    socket
    |> assign(selected_control_group_id: nil)
    |> load_selected()
  end

  def persist_selected(socket) do
    case {socket.assigns.selected_pico, socket.assigns.selected_control_group_id} do
      {%{} = device, group_id} when is_binary(group_id) ->
        attrs = %{
          "id" => group_id,
          "name" => socket.assigns.control_group_name,
          "group_ids" => socket.assigns.control_group_group_ids,
          "light_ids" => socket.assigns.control_group_light_ids
        }

        case Picos.save_control_group(device, attrs) do
          {:ok, updated} ->
            socket
            |> assign(save_status: nil, save_error: nil)
            |> Loader.reload_from_devices(
              Picos.list_devices_for_bridge(socket.assigns.bridge.id),
              updated.id
            )
            |> select(group_id)

          {:error, :invalid_targets} ->
            assign(
              socket,
              save_status: nil,
              save_error: "Control group targets must stay in the Pico room."
            )

          {:error, :invalid_name} ->
            assign(socket, save_status: nil, save_error: "Control groups need a name.")

          {:error, reason} ->
            assign(socket, save_status: nil, save_error: inspect(reason))
        end

      _ ->
        socket
    end
  end

  def persist_selected_name(socket) do
    trimmed_name = String.trim(socket.assigns.control_group_name_draft || "")

    case {socket.assigns.selected_pico, socket.assigns.selected_control_group_id, trimmed_name} do
      {%{} = device, group_id, name} when is_binary(group_id) and name != "" ->
        attrs = %{
          "id" => group_id,
          "name" => name,
          "group_ids" => socket.assigns.control_group_group_ids,
          "light_ids" => socket.assigns.control_group_light_ids
        }

        case Picos.save_control_group(device, attrs) do
          {:ok, updated} ->
            socket
            |> assign(
              save_status: "Control group name updated.",
              save_error: nil,
              editing_control_group_name: false
            )
            |> Loader.reload_from_devices(
              Picos.list_devices_for_bridge(socket.assigns.bridge.id),
              updated.id
            )
            |> select(group_id)

          {:error, :invalid_targets} ->
            assign(
              socket,
              save_status: nil,
              save_error: "Control group targets must stay in the Pico room."
            )

          {:error, :invalid_name} ->
            assign(socket, save_status: nil, save_error: "Control groups need a name.")

          {:error, reason} ->
            assign(socket, save_status: nil, save_error: inspect(reason))
        end

      {_, _, ""} ->
        assign(socket, save_status: nil, save_error: "Control groups need a name.")

      _ ->
        socket
    end
  end

  def next_name(control_groups) when is_list(control_groups) do
    existing_names =
      control_groups
      |> Enum.map(&Map.get(&1, "name"))
      |> MapSet.new()

    Stream.iterate(1, &(&1 + 1))
    |> Enum.find_value(fn number ->
      name = "Control Group #{number}"

      if MapSet.member?(existing_names, name), do: nil, else: name
    end)
  end

  def available_lights(%{room_id: room_id}, lights, group_ids, light_ids)
      when is_integer(room_id) and is_list(lights) do
    covered_light_ids = covered_light_ids(room_id, group_ids, light_ids)

    Enum.reject(lights, &MapSet.member?(covered_light_ids, &1.id))
  end

  def available_lights(_device, lights, _group_ids, light_ids) when is_list(lights) do
    Enum.reject(lights, &(&1.id in light_ids))
  end

  def available_groups(%{room_id: room_id}, groups, group_ids, light_ids)
      when is_integer(room_id) and is_list(groups) do
    covered_light_ids = covered_light_ids(room_id, group_ids, light_ids)
    selected_group_ids = MapSet.new(group_ids)

    Enum.reject(groups, fn group ->
      group.id in selected_group_ids or
        available_group_light_ids(room_id, group.id, covered_light_ids) == []
    end)
  end

  def available_groups(_device, groups, group_ids, _light_ids) when is_list(groups) do
    Enum.reject(groups, &(&1.id in group_ids))
  end

  def picker_dom_id(kind, entities) when kind in ["group", "light"] do
    "pico-control-group-#{kind}-picker-#{picker_dom_suffix(entities)}"
  end

  def picker_select_id(kind, entities) when kind in ["group", "light"] do
    "pico-control-group-#{kind}-select-#{picker_dom_suffix(entities)}"
  end

  defp covered_light_ids(room_id, group_ids, light_ids) when is_integer(room_id) do
    room_id
    |> Hueworks.Picos.Targets.expand_room_targets(group_ids, light_ids)
    |> MapSet.new()
  end

  defp available_group_light_ids(room_id, group_id, covered_light_ids)
       when is_integer(room_id) and is_integer(group_id) do
    room_id
    |> Hueworks.Picos.Targets.expand_room_targets([group_id], [])
    |> Enum.reject(&MapSet.member?(covered_light_ids, &1))
  end

  defp picker_dom_suffix(entities) when is_list(entities) do
    entities
    |> Enum.map_join("-", &Integer.to_string(&1.id))
    |> case do
      "" -> "empty"
      suffix -> suffix
    end
  end
end
