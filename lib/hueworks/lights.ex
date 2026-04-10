defmodule Hueworks.Lights do
  @moduledoc """
  Query helpers for lights.
  """

  import Ecto.Query, only: [from: 2]

  alias Hueworks.HomeAssistant.Export, as: HomeAssistantExport
  alias Hueworks.Kelvin
  alias Hueworks.Util
  alias Hueworks.Schemas.Group
  alias Hueworks.Schemas.GroupLight
  alias Hueworks.Schemas.Light
  alias Hueworks.Repo

  def list_controllable_lights(include_disabled \\ false, include_linked \\ false) do
    excluded_light_ids =
      from(gl in GroupLight,
        join: g in Group,
        on: g.id == gl.group_id,
        where: not is_nil(g.canonical_group_id),
        select: gl.light_id
      )

    query =
      from(l in Light,
        where: l.id not in subquery(excluded_light_ids),
        order_by: [asc: l.name]
      )

    query
    |> maybe_filter_linked(include_linked)
    |> maybe_filter_enabled(include_disabled)
    |> Repo.all()
  end

  def list_link_targets(%Light{id: light_id}) do
    from(l in Light,
      where: l.id != ^light_id and is_nil(l.canonical_light_id),
      order_by: [asc: l.name]
    )
    |> Repo.all()
  end

  def get_light(id), do: Repo.get(Light, id)

  def update_display_name(light, attrs) when is_map(attrs) do
    attrs =
      attrs
      |> Map.update(:display_name, nil, &Util.normalize_display_name/1)
      |> normalize_kelvin_attrs()

    case light
         |> Light.changeset(attrs)
         |> Repo.update() do
      {:ok, updated} ->
        HomeAssistantExport.refresh_light(updated.id)
        {:ok, updated}

      other ->
        other
    end
  end

  def update_display_name(light, display_name) do
    update_display_name(light, %{display_name: display_name})
  end

  def update_link(%Light{} = light, canonical_light_id) do
    canonical_light_id =
      case canonical_light_id do
        id when is_integer(id) -> id
        _ -> nil
      end

    with :ok <- validate_no_dependents(light, canonical_light_id),
         :ok <- validate_link_target(canonical_light_id) do
      light
      |> Light.changeset(%{canonical_light_id: canonical_light_id})
      |> Repo.update()
    end
  end

  defp normalize_kelvin_attrs(attrs) do
    attrs
    |> Map.update(:actual_min_kelvin, nil, &Util.normalize_kelvin/1)
    |> Map.update(:actual_max_kelvin, nil, &Util.normalize_kelvin/1)
    |> Map.update(:extended_min_kelvin, nil, &Util.normalize_kelvin/1)
  end

  defp validate_no_dependents(_light, nil), do: :ok

  defp validate_no_dependents(%Light{id: light_id}, canonical_light_id)
       when is_integer(light_id) and is_integer(canonical_light_id) do
    has_dependents? =
      Repo.exists?(
        from(l in Light,
          where: l.canonical_light_id == ^light_id
        )
      )

    if has_dependents?, do: {:error, :has_linked_dependents}, else: :ok
  end

  defp validate_link_target(nil), do: :ok

  defp validate_link_target(canonical_light_id) when is_integer(canonical_light_id) do
    case Repo.get(Light, canonical_light_id) do
      nil ->
        {:error, :invalid_canonical_light}

      %Light{canonical_light_id: nil} ->
        :ok

      %Light{} ->
        {:error, :invalid_canonical_light}
    end
  end

  def temp_range(entity), do: Kelvin.derive_range(entity)

  defp maybe_filter_linked(query, true), do: query

  defp maybe_filter_linked(query, false) do
    from(l in query, where: is_nil(l.canonical_light_id))
  end

  defp maybe_filter_enabled(query, true), do: query

  defp maybe_filter_enabled(query, false) do
    from(l in query, where: l.enabled == true)
  end
end
