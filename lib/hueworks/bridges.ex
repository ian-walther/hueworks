defmodule Hueworks.Bridges do
  @moduledoc """
  Bridge lifecycle helpers.
  """

  import Ecto.Query, only: [from: 2]

  alias Hueworks.Repo
  alias Hueworks.Schemas.{Bridge, Group, GroupLight, Light, SceneComponentLight}

  def delete_entities(%Bridge{} = bridge) do
    Repo.transaction(fn ->
      light_ids =
        Repo.all(from(l in Light, where: l.bridge_id == ^bridge.id, select: l.id))

      group_ids =
        Repo.all(from(g in Group, where: g.bridge_id == ^bridge.id, select: g.id))

      if light_ids != [] do
        Repo.delete_all(from(scl in SceneComponentLight, where: scl.light_id in ^light_ids))
        Repo.delete_all(from(gl in GroupLight, where: gl.light_id in ^light_ids))
      end

      if group_ids != [] do
        Repo.delete_all(from(gl in GroupLight, where: gl.group_id in ^group_ids))
      end

      Repo.delete_all(from(g in Group, where: g.bridge_id == ^bridge.id))
      Repo.delete_all(from(l in Light, where: l.bridge_id == ^bridge.id))

      Repo.update_all(
        from(b in Bridge, where: b.id == ^bridge.id),
        set: [import_complete: false]
      )

      :ok
    end)
  end

  def delete_unchecked_entities(%Bridge{} = bridge, light_external_ids, group_external_ids) do
    Repo.transaction(fn ->
      light_ids =
        light_external_ids
        |> normalize_ids()
        |> fetch_light_ids(bridge.id)

      group_ids =
        group_external_ids
        |> normalize_ids()
        |> fetch_group_ids(bridge.id)

      if light_ids != [] do
        Repo.delete_all(from(scl in SceneComponentLight, where: scl.light_id in ^light_ids))
        Repo.delete_all(from(gl in GroupLight, where: gl.light_id in ^light_ids))
      end

      if group_ids != [] do
        Repo.delete_all(from(gl in GroupLight, where: gl.group_id in ^group_ids))
      end

      if group_ids != [] do
        Repo.delete_all(from(g in Group, where: g.id in ^group_ids))
      end

      if light_ids != [] do
        Repo.delete_all(from(l in Light, where: l.id in ^light_ids))
      end

      :ok
    end)
  end

  def delete_bridge(%Bridge{} = bridge) do
    Repo.delete(bridge)
  end

  defp normalize_ids(ids) do
    ids
    |> List.wrap()
    |> Enum.filter(&is_binary/1)
    |> Enum.uniq()
  end

  defp fetch_light_ids([], _bridge_id), do: []

  defp fetch_light_ids(external_ids, bridge_id) do
    Repo.all(
      from(l in Light,
        where: l.bridge_id == ^bridge_id and l.external_id in ^external_ids,
        select: l.id
      )
    )
  end

  defp fetch_group_ids([], _bridge_id), do: []

  defp fetch_group_ids(external_ids, bridge_id) do
    Repo.all(
      from(g in Group,
        where: g.bridge_id == ^bridge_id and g.external_id in ^external_ids,
        select: g.id
      )
    )
  end
end
