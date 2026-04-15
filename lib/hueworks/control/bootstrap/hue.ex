defmodule Hueworks.Control.Bootstrap.Hue do
  @moduledoc false

  import Ecto.Query, only: [from: 2]

  alias Hueworks.Control.Indexes
  alias Hueworks.Control.StateParser
  alias Hueworks.Repo
  alias Hueworks.Schemas.Bridge
  alias Hueworks.Control.State

  def run do
    bridges = Repo.all(from(b in Bridge, where: b.type == :hue and b.enabled == true))

    Enum.each(bridges, fn bridge ->
      api_key = Bridge.credentials_struct(bridge).api_key

      if is_binary(api_key) and api_key != "" do
        lights = fetch_hue_endpoint(bridge.host, api_key, "/lights")
        groups = fetch_hue_endpoint(bridge.host, api_key, "/groups")
        lights_by_id = Indexes.lights_by_source_id(bridge.id, :hue)
        groups_by_id = Indexes.groups_by_source_id(bridge.id, :hue)

        Enum.each(lights, fn {id, light} ->
          case Map.get(lights_by_id, to_string(id)) do
            nil ->
              :ok

            db_light ->
              state = build_hue_light_state(light)
              State.put(:light, db_light.id, state, source: :bootstrap)
          end
        end)

        Enum.each(groups, fn {id, group} ->
          case Map.get(groups_by_id, to_string(id)) do
            nil ->
              :ok

            db_group ->
              state = build_hue_group_state(group)
              State.put(:group, db_group.id, state, source: :bootstrap)
          end
        end)
      end
    end)
  end

  defp fetch_hue_endpoint(host, api_key, endpoint) do
    url = "http://#{host}/api/#{api_key}#{endpoint}"

    case HTTPoison.get(url, [], recv_timeout: 10_000) do
      {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
        case Jason.decode(body) do
          {:ok, data} when is_map(data) -> data
          _ -> %{}
        end

      _ ->
        %{}
    end
  end

  defp build_hue_light_state(light) when is_map(light) do
    StateParser.hue_v1_state(light, "state")
  end

  defp build_hue_light_state(_light), do: %{}

  defp build_hue_group_state(group) when is_map(group) do
    StateParser.hue_v1_state(group, "action")
  end

  defp build_hue_group_state(_group), do: %{}
end
