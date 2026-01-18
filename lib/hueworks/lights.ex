defmodule Hueworks.Lights do
  @moduledoc """
  Query helpers for lights.
  """

  import Ecto.Query, only: [from: 2]

  alias Hueworks.Kelvin
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

  def temp_range(entity), do: Kelvin.derive_range(entity)

  defp maybe_filter_enabled(query, true), do: query

  defp maybe_filter_enabled(query, false) do
    from(l in query, where: l.enabled == true)
  end
end
