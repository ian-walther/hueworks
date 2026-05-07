defmodule Hueworks.Scenes.Persistence do
  @moduledoc false

  alias Hueworks.HomeAssistant.Export, as: HomeAssistantExport
  alias Hueworks.HomeKit
  alias Hueworks.Repo
  alias Hueworks.Schemas.Scene

  def create(attrs) when is_map(attrs) do
    %Scene{}
    |> Scene.changeset(attrs)
    |> Repo.insert()
    |> sync_create()
  end

  def update(%Scene{} = scene, attrs) when is_map(attrs) do
    scene
    |> Scene.changeset(attrs)
    |> Repo.update()
    |> sync_update()
  end

  def delete(%Scene{} = scene) do
    scene
    |> Repo.delete()
    |> sync_delete()
  end

  defp sync_create({:ok, scene}) do
    scene
    |> HomeAssistantExport.refresh_scene()

    scene.room_id
    |> HomeAssistantExport.refresh_room()

    HomeKit.reload()

    {:ok, scene}
  end

  defp sync_create(other), do: other

  defp sync_update({:ok, scene}) do
    scene
    |> HomeAssistantExport.refresh_scene()

    scene.room_id
    |> HomeAssistantExport.refresh_room()

    HomeKit.reload()

    {:ok, scene}
  end

  defp sync_update(other), do: other

  defp sync_delete({:ok, scene}) do
    scene
    |> HomeAssistantExport.remove_scene()

    scene.room_id
    |> HomeAssistantExport.refresh_room()

    HomeKit.reload()

    {:ok, scene}
  end

  defp sync_delete(other), do: other
end
