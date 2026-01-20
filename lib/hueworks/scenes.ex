defmodule Hueworks.Scenes do
  @moduledoc """
  Query helpers for scenes.
  """

  import Ecto.Query, only: [from: 2]

  alias Hueworks.Repo
  alias Hueworks.Schemas.Scene

  def list_scenes_for_room(room_id) do
    Repo.all(from(s in Scene, where: s.room_id == ^room_id, order_by: [asc: s.name]))
  end

  def create_scene(attrs) do
    %Scene{}
    |> Scene.changeset(attrs)
    |> Repo.insert()
  end

  def get_scene(id), do: Repo.get(Scene, id)

  def update_scene(scene, attrs) do
    scene
    |> Scene.changeset(attrs)
    |> Repo.update()
  end

  def delete_scene(scene) do
    Repo.delete(scene)
  end
end
