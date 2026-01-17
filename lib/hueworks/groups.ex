defmodule Hueworks.Groups do
  @moduledoc """
  Query helpers for groups.
  """

  import Ecto.Query, only: [from: 2]

  alias Hueworks.Schemas.Group
  alias Hueworks.Repo

  def list_controllable_groups do
    Repo.all(
      from(g in Group,
        where: is_nil(g.canonical_group_id) and g.enabled == true,
        order_by: [asc: g.name]
      )
    )
  end

  def get_group(id), do: Repo.get(Group, id)
end
