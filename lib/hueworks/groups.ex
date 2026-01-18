defmodule Hueworks.Groups do
  @moduledoc """
  Query helpers for groups.
  """

  import Ecto.Query, only: [from: 2]

  alias Hueworks.Schemas.Group
  alias Hueworks.Repo

  def list_controllable_groups(include_disabled \\ false) do
    query =
      from(g in Group,
        where: is_nil(g.canonical_group_id),
        order_by: [asc: g.name]
      )

    query
    |> maybe_filter_enabled(include_disabled)
    |> Repo.all()
  end

  def get_group(id), do: Repo.get(Group, id)

  def update_display_name(group, attrs) when is_map(attrs) do
    attrs =
      attrs
      |> Map.update(:display_name, nil, &normalize_display_name/1)
      |> normalize_kelvin_attrs()

    group
    |> Group.changeset(attrs)
    |> Repo.update()
  end

  def update_display_name(group, display_name) do
    update_display_name(group, %{display_name: display_name})
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

  defp maybe_filter_enabled(query, true), do: query

  defp maybe_filter_enabled(query, false) do
    from(g in query, where: g.enabled == true)
  end
end
