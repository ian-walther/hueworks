defmodule Hueworks.Import.NormalizeFromDb do
  @moduledoc false

  import Ecto.Query, only: [from: 2]

  alias Hueworks.Repo
  alias Hueworks.Schemas.{Bridge, Group, GroupLight, Light}

  def normalize(%Bridge{} = bridge) do
    lights =
      Repo.all(from(l in Light, where: l.bridge_id == ^bridge.id, select: l.normalized_json))
      |> Enum.filter(&is_map/1)

    groups =
      Repo.all(from(g in Group, where: g.bridge_id == ^bridge.id, select: g.normalized_json))
      |> Enum.filter(&is_map/1)

    memberships = %{
      group_lights: group_lights(bridge.id),
      room_groups: [],
      room_lights: []
    }

    %{
      schema_version: 1,
      bridge: %{
        id: bridge.id,
        type: bridge.type,
        name: bridge.name,
        host: bridge.host
      },
      normalized_at: DateTime.utc_now() |> DateTime.to_iso8601(),
      rooms: [],
      groups: groups,
      lights: lights,
      memberships: memberships
    }
  end

  defp group_lights(bridge_id) do
    Repo.all(
      from(gl in GroupLight,
        join: g in Group,
        on: g.id == gl.group_id,
        join: l in Light,
        on: l.id == gl.light_id,
        where: g.bridge_id == ^bridge_id and l.bridge_id == ^bridge_id,
        select: {g.normalized_json, l.normalized_json}
      )
    )
    |> Enum.reduce([], fn {group_json, light_json}, acc ->
      group_id = get_source_id(group_json)
      light_id = get_source_id(light_json)

      if is_binary(group_id) and is_binary(light_id) do
        [%{group_source_id: group_id, light_source_id: light_id} | acc]
      else
        acc
      end
    end)
    |> Enum.reverse()
  end

  defp get_source_id(%{"source_id" => source_id}) when is_binary(source_id), do: source_id
  defp get_source_id(_value), do: nil
end
