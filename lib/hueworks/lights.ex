defmodule Hueworks.Lights do
  @moduledoc """
  Query helpers for lights.
  """

  import Ecto.Query, only: [from: 2]

  alias Hueworks.Lights.Light
  alias Hueworks.Repo

  def list_controllable_lights do
    Repo.all(
      from(l in Light,
        where: is_nil(l.canonical_light_id) and l.enabled == true,
        order_by: [asc: l.name]
      )
    )
  end

  def get_light(id), do: Repo.get(Light, id)
end
