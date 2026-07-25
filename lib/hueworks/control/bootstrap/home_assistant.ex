defmodule Hueworks.Control.Bootstrap.HomeAssistant do
  @moduledoc false

  import Ecto.Query, only: [from: 2]

  alias Hueworks.Control.Indexes
  alias Hueworks.Control.HomeAssistantBridge
  alias Hueworks.Control.StateParser
  alias Hueworks.HomeAssistant.Host
  alias Hueworks.Repo
  alias Hueworks.Schemas.Bridge
  alias Hueworks.Control.State

  def run do
    Bridge
    |> where_enabled_home_assistant()
    |> Repo.all()
    |> Enum.each(&bootstrap_bridge/1)

    :ok
  end

  defp where_enabled_home_assistant(queryable) do
    from(b in queryable, where: b.type == :ha and b.enabled == true)
  end

  defp bootstrap_bridge(%Bridge{} = bridge) do
    result =
      HomeAssistantBridge.request(%{bridge_id: bridge.id}, fn host, token ->
        fetch_ha_states(host, token)
      end)

    case result do
      {:ok, states} ->
        lights_by_id = Indexes.lights_by_source_id(bridge.id, :ha)
        groups_by_id = Indexes.groups_by_source_id(bridge.id, :ha)

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

      {:error, _reason} ->
        :ok
    end
  end

  defp fetch_ha_states(host, token) do
    url = Host.http_url(host, "/api/states")
    headers = [{"Authorization", "Bearer #{token}"}, {"Content-Type", "application/json"}]

    case HTTPoison.get(url, headers, recv_timeout: 10_000) do
      {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
        case Jason.decode(body) do
          {:ok, data} when is_list(data) -> {:ok, data}
          _ -> {:error, :invalid_response}
        end

      {:ok, %HTTPoison.Response{status_code: status, body: body}} ->
        {:error, {:http_error, status, body}}

      {:error, %HTTPoison.Error{reason: reason}} ->
        {:error, {:http_error, reason}}
    end
  end

  defp build_ha_state(state, attrs, entity_id, lights_by_id, groups_by_id) do
    entity = Map.get(lights_by_id, entity_id) || Map.get(groups_by_id, entity_id)
    StateParser.home_assistant_state(%{"state" => state, "attributes" => attrs}, entity)
  end
end
