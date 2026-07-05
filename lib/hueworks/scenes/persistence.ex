defmodule Hueworks.Scenes.Persistence do
  @moduledoc false

  alias Hueworks.DomainEvents
  alias Hueworks.Repo
  alias Hueworks.Schemas.Scene

  def create(attrs) when is_map(attrs) do
    %Scene{}
    |> Scene.changeset(attrs)
    |> Repo.insert()
    |> sync_upsert()
  end

  def update(%Scene{} = scene, attrs) when is_map(attrs) do
    scene
    |> Scene.changeset(attrs)
    |> Repo.update()
    |> sync_upsert()
  end

  def delete(%Scene{} = scene) do
    scene
    |> Repo.delete()
    |> sync_delete()
  end

  defp sync_upsert({:ok, scene}) do
    DomainEvents.scene_saved(scene)
    {:ok, scene}
  end

  defp sync_upsert(other), do: other

  defp sync_delete({:ok, scene}) do
    DomainEvents.scene_deleted(scene)
    {:ok, scene}
  end

  defp sync_delete(other), do: other
end
