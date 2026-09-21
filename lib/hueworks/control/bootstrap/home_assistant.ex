defmodule Hueworks.Control.Bootstrap.HomeAssistant do
  @moduledoc false

  import Ecto.Query, only: [from: 2]

  alias Hueworks.Control.Bootstrap.Observations
  alias Hueworks.Control.HomeAssistantBridge
  alias Hueworks.Control.Indexes
  alias Hueworks.Control.StateParser
  alias Hueworks.HomeAssistant.Host
  alias Hueworks.Repo
  alias Hueworks.Schemas.Bridge

  def run do
    Bridge
    |> where_enabled_home_assistant()
    |> Repo.all()
    |> Enum.each(&run/1)

    :ok
  end

  defp where_enabled_home_assistant(queryable) do
    from(b in queryable, where: b.type == :ha and b.enabled == true)
  end

  def run(%Bridge{} = bridge, opts \\ []) do
    with :ok <- Hueworks.RuntimeIO.ensure_enabled() do
      bootstrap_bridge(bridge, opts)
    end
  end

  defp bootstrap_bridge(bridge, opts) do
    lights = Observations.capture(:light, Indexes.lights_by_source_id(bridge.id, :ha))
    groups = Observations.capture(:group, Indexes.groups_by_source_id(bridge.id, :ha))
    get = Keyword.get(opts, :http_get, &HTTPoison.get/3)

    result =
      HomeAssistantBridge.request(%{bridge_id: bridge.id}, fn host, token ->
        fetch_ha_states(host, token, get)
      end)

    case result do
      {:ok, states} ->
        Enum.each(states, fn state ->
          hydrate(state, :light, lights)
          hydrate(state, :group, groups)
        end)

        :ok

      {:error, _reason} = error ->
        error
    end
  end

  defp fetch_ha_states(host, token, get) do
    url = Host.http_url(host, "/api/states")
    headers = [{"Authorization", "Bearer #{token}"}, {"Content-Type", "application/json"}]

    case get.(url, headers, recv_timeout: 10_000, timeout: 5_000) do
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

  defp hydrate(state, type, observations) do
    case Map.get(observations, state["entity_id"]) do
      {entity, _version} = entry ->
        Observations.put(type, entry, StateParser.home_assistant_state(state, entity))

      nil ->
        :ok
    end
  end
end
