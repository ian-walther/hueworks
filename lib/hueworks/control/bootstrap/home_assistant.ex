defmodule Hueworks.Control.Bootstrap.HomeAssistant do
  @moduledoc false

  import Ecto.Query, only: [from: 2]

  alias Hueworks.Control.Indexes
  alias Hueworks.Control.StateParser
  alias Hueworks.HomeAssistant.Host
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
    |> Map.merge(StateParser.power_map(state))
    |> Map.merge(StateParser.brightness_from_0_255(attrs["brightness"]))
    |> Map.merge(StateParser.kelvin_from_ha_attrs(attrs, entity))
  end
end
