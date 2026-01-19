defmodule Hueworks.Rooms do
  @moduledoc """
  Query helpers for rooms.
  """

  import Ecto.Query, only: [from: 2]

  alias Hueworks.Repo
  alias Hueworks.Schemas.Room

  def list_rooms do
    Repo.all(from(r in Room, order_by: [asc: r.name]))
  end

  def list_rooms_with_children do
    Repo.all(from(r in Room, order_by: [asc: r.name]))
    |> Repo.preload([:groups, :lights])
  end

  def get_room(id), do: Repo.get(Room, id)

  def create_room(attrs) do
    %Room{}
    |> Room.changeset(attrs)
    |> Repo.insert()
  end

  def update_room(room, attrs) do
    room
    |> Room.changeset(attrs)
    |> Repo.update()
  end

  def delete_room(room) do
    Repo.delete(room)
  end
end
