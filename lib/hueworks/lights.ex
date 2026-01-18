defmodule Hueworks.Lights do
  @moduledoc """
  Query helpers for lights.
  """

  import Ecto.Query, only: [from: 2]

  alias Hueworks.Schemas.Group
  alias Hueworks.Schemas.GroupLight
  alias Hueworks.Schemas.Light
  alias Hueworks.Repo

  def list_controllable_lights(include_disabled \\ false) do
    excluded_light_ids =
      from(gl in GroupLight,
        join: g in Group,
        on: g.id == gl.group_id,
        where: not is_nil(g.canonical_group_id),
        select: gl.light_id
      )

    query =
      from(l in Light,
        where:
          is_nil(l.canonical_light_id) and
            l.id not in subquery(excluded_light_ids),
        order_by: [asc: l.name]
      )

    query
    |> maybe_filter_enabled(include_disabled)
    |> Repo.all()
  end

  def get_light(id), do: Repo.get(Light, id)

  def update_display_name(light, attrs) when is_map(attrs) do
    attrs =
      attrs
      |> Map.update(:display_name, nil, &normalize_display_name/1)
      |> normalize_kelvin_attrs()

    light
    |> Light.changeset(attrs)
    |> Repo.update()
  end

  def update_display_name(light, display_name) do
    update_display_name(light, %{display_name: display_name})
  end

  defp normalize_display_name(display_name) when is_binary(display_name) do
    display_name = String.trim(display_name)
    if display_name == "", do: nil, else: display_name
  end

  defp normalize_display_name(_display_name), do: nil

  defp normalize_kelvin_attrs(attrs) do
    attrs
    |> Map.update(:actual_min_kelvin, nil, &normalize_kelvin/1)
    |> Map.update(:actual_max_kelvin, nil, &normalize_kelvin/1)
  end

  defp normalize_kelvin(nil), do: nil
  defp normalize_kelvin(value) when is_integer(value), do: value

  defp normalize_kelvin(value) when is_binary(value) do
    value = String.trim(value)

    case Integer.parse(value) do
      {int, ""} -> int
      _ -> nil
    end
  end

  defp normalize_kelvin(_value), do: nil

  def temp_range(entity) do
    min_kelvin =
      Map.get(entity, :actual_min_kelvin) ||
        Map.get(entity, "actual_min_kelvin") ||
        Map.get(entity, :reported_min_kelvin) ||
        Map.get(entity, "reported_min_kelvin")

    max_kelvin =
      Map.get(entity, :actual_max_kelvin) ||
        Map.get(entity, "actual_max_kelvin") ||
        Map.get(entity, :reported_max_kelvin) ||
        Map.get(entity, "reported_max_kelvin")

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

  defp maybe_filter_enabled(query, true), do: query

  defp maybe_filter_enabled(query, false) do
    from(l in query, where: l.enabled == true)
  end
end
