defmodule Hueworks.Control.Bootstrap.HomeAssistant do
  @moduledoc false

  import Ecto.Query, only: [from: 2]

  alias Hueworks.Control.Indexes
  alias Hueworks.Util
  alias Hueworks.HomeAssistant.Host
  alias Hueworks.Kelvin
  alias Hueworks.Repo
  alias Hueworks.Schemas.Bridge
  alias Hueworks.Control.State

  def run do
    bridge = Repo.one(from(b in Bridge, where: b.type == :ha and b.enabled == true))

    if bridge do
      token = bridge.credentials["token"]

      if is_binary(token) and token != "" do
        lights_by_id = Indexes.lights_by_source_id(bridge.id, :ha)
        groups_by_id = Indexes.groups_by_source_id(bridge.id, :ha)
        states = fetch_ha_states(bridge.host, token)

        Enum.each(states, fn state ->
          entity_id = state["entity_id"]
          attrs = state["attributes"] || %{}
          current = build_ha_state(state["state"], attrs, entity_id, lights_by_id, groups_by_id)

          case Map.get(lights_by_id, entity_id) do
            nil -> :ok
            db_light -> State.put(:light, db_light.id, current)
          end

          case Map.get(groups_by_id, entity_id) do
            nil -> :ok
            db_group -> State.put(:group, db_group.id, current)
          end
        end)
      end
    end
  end

  defp fetch_ha_states(host, token) do
    url = "http://#{Host.normalize(host)}/api/states"
    headers = [{"Authorization", "Bearer #{token}"}, {"Content-Type", "application/json"}]

    case HTTPoison.get(url, headers, recv_timeout: 10_000) do
      {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
        case Jason.decode(body) do
          {:ok, data} when is_list(data) -> data
          _ -> []
        end

      _ ->
        []
    end
  end

  defp build_ha_state(state, attrs, entity_id, lights_by_id, groups_by_id) do
    entity = Map.get(lights_by_id, entity_id) || Map.get(groups_by_id, entity_id)

    %{}
    |> maybe_put_power(state)
    |> maybe_put_brightness(attrs["brightness"])
    |> maybe_put_kelvin(attrs, entity)
  end

  defp maybe_put_power(acc, true), do: Map.put(acc, :power, :on)
  defp maybe_put_power(acc, false), do: Map.put(acc, :power, :off)
  defp maybe_put_power(acc, "on"), do: Map.put(acc, :power, :on)
  defp maybe_put_power(acc, "off"), do: Map.put(acc, :power, :off)
  defp maybe_put_power(acc, _), do: acc

  defp maybe_put_brightness(acc, brightness) when is_number(brightness) do
    percent = round(brightness / 255 * 100)
    Map.put(acc, :brightness, Util.clamp(percent, 1, 100))
  end

  defp maybe_put_brightness(acc, _), do: acc

  defp maybe_put_kelvin(acc, attrs, entity) when is_map(attrs) do
    cond do
      is_number(attrs["color_temp_kelvin"]) ->
        kelvin = Kelvin.map_from_event(entity, round(attrs["color_temp_kelvin"]))
        Map.put(acc, :kelvin, kelvin)

      is_number(attrs["color_temp"]) and attrs["color_temp"] > 0 ->
        kelvin = round(1_000_000 / attrs["color_temp"])
        Map.put(acc, :kelvin, Kelvin.map_from_event(entity, kelvin))

      true ->
        acc
    end
  end

  defp maybe_put_kelvin(acc, _attrs, _entity), do: acc


end