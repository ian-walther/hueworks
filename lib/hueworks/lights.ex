defmodule Hueworks.Lights do
  @moduledoc """
  Query helpers for lights.
  """

  import Ecto.Query, only: [from: 2]

  alias Hueworks.Schemas.Group
  alias Hueworks.Schemas.GroupLight
  alias Hueworks.Schemas.Light
  alias Hueworks.Repo

  def list_controllable_lights do
    excluded_light_ids =
      from(gl in GroupLight,
        join: g in Group,
        on: g.id == gl.group_id,
        where: not is_nil(g.canonical_group_id),
        select: gl.light_id
      )

    Repo.all(
      from(l in Light,
        where:
          is_nil(l.canonical_light_id) and l.enabled == true and
            l.id not in subquery(excluded_light_ids),
        order_by: [asc: l.name]
      )
    )
  end

  def get_light(id), do: Repo.get(Light, id)

  def temp_range(entity) do
    min_kelvin = Map.get(entity, :min_kelvin) || Map.get(entity, "min_kelvin")
    max_kelvin = Map.get(entity, :max_kelvin) || Map.get(entity, "max_kelvin")

    cond do
      is_number(min_kelvin) and is_number(max_kelvin) ->
        {round(min_kelvin), round(max_kelvin)}

      true ->
        case mired_range(entity) do
          {min_mired, max_mired} when min_mired > 0 and max_mired > 0 ->
            min_k = round(1_000_000 / max_mired)
            max_k = round(1_000_000 / min_mired)
            {min_k, max_k}

          _ ->
            {2000, 6500}
        end
    end
  end

  defp mired_range(%{metadata: metadata}) when is_map(metadata) do
    capabilities = Map.get(metadata, "capabilities") || %{}
    control = get_nested(capabilities, "control") || %{}
    ct = get_nested(control, "ct") || %{}
    min_mired = get_nested(ct, "min")
    max_mired = get_nested(ct, "max")

    if is_number(min_mired) and is_number(max_mired) do
      {min_mired, max_mired}
    else
      nil
    end
  end

  defp mired_range(_entity), do: nil

  defp get_nested(map, key) when is_map(map) and is_binary(key) do
    Map.get(map, key) ||
      try do
        Map.get(map, String.to_existing_atom(key))
      rescue
        ArgumentError -> nil
      end
  end

  defp get_nested(map, key) when is_map(map) and is_atom(key) do
    Map.get(map, key)
  end

  defp get_nested(_map, _key), do: nil
end
