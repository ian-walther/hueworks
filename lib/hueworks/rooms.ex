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
    |> Repo.preload([:groups, :lights, :scenes])
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

  def set_occupied(room_id, value) when is_integer(room_id) and is_boolean(value) do
    Repo.update_all(
      from(r in Room, where: r.id == ^room_id),
      set: [occupied: value]
    )

    :ok
  end

  def room_occupied?(room_id) when is_integer(room_id) do
    case Repo.one(from(r in Room, where: r.id == ^room_id, select: r.occupied)) do
      nil -> true
      value -> value
    end
  end

  def delete_room(room) do
    Repo.delete(room)
  end
end
