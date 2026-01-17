defmodule Hueworks.Lights do
  @moduledoc """
  Query helpers for lights.
  """

  import Ecto.Query, only: [from: 2]

  alias Hueworks.Groups.Group
  alias Hueworks.Groups.GroupLight
  alias Hueworks.Lights.Light
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
end
