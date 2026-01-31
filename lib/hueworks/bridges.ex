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

  def delete_bridge(%Bridge{} = bridge) do
    Repo.delete(bridge)
  end
end
