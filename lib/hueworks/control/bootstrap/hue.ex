defmodule Hueworks.Control.Bootstrap.Hue do
  @moduledoc false

  import Ecto.Query, only: [from: 2]

  alias Hueworks.Control.Bootstrap.Observations
  alias Hueworks.Control.Indexes
  alias Hueworks.Control.StateParser
  alias Hueworks.Repo
  alias Hueworks.Schemas.Bridge

  def run do
    bridges = Repo.all(from(b in Bridge, where: b.type == :hue and b.enabled == true))

    Enum.each(bridges, &run/1)
    :ok
  end

  def run(%Bridge{} = bridge, opts \\ []) do
    with :ok <- Hueworks.RuntimeIO.ensure_enabled(),
         key when is_binary(key) and key != "" <- Bridge.credentials_struct(bridge).api_key do
      lights = Observations.capture(:light, Indexes.lights_by_source_id(bridge.id, :hue))
      groups = Observations.capture(:group, Indexes.groups_by_source_id(bridge.id, :hue))
      get = Keyword.get(opts, :http_get, &HTTPoison.get/3)

      with {:ok, light_states} <- fetch_hue_endpoint(bridge.host, key, "/lights", get),
           {:ok, group_states} <- fetch_hue_endpoint(bridge.host, key, "/groups", get) do
        hydrate(light_states, lights, :light, "state")
        hydrate(group_states, groups, :group, "action")
        :ok
      end
    else
      {:error, _} = error -> error
      _ -> {:error, :missing_credentials}
    end
  end

  defp hydrate(states, observations, type, state_key) do
    Enum.each(states, fn {id, resource} ->
      if entry = Map.get(observations, to_string(id)) do
        Observations.put(type, entry, StateParser.hue_v1_state(resource, state_key))
      end
    end)
  end

  defp fetch_hue_endpoint(host, api_key, endpoint, get) do
    url = "http://#{host}/api/#{api_key}#{endpoint}"

    case get.(url, [], recv_timeout: 10_000, timeout: 5_000) do
      {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
        case Jason.decode(body) do
          {:ok, data} when is_map(data) -> {:ok, data}
          _ -> {:error, :invalid_response}
        end

      _ ->
        {:error, :request_failed}
    end
  end
end
