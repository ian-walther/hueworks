defmodule HueworksWeb.ExternalSceneConfigLiveTest do
  use HueworksWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Hueworks.ExternalScenes
  alias Hueworks.Repo
  alias Hueworks.Schemas.{Bridge, Room}
  alias Hueworks.Scenes

  test "scene config page syncs HA scenes and saves mappings", %{conn: conn} do
    bridge =
      Repo.insert!(%Bridge{
        type: :ha,
        name: "Home Assistant",
        host: "10.0.0.91",
        credentials: %{"token" => "token"},
        enabled: true,
        import_complete: true
      })

    room = Repo.insert!(%Room{name: "Living"})
    {:ok, scene} = Scenes.create_scene(%{name: "Movie", room_id: room.id})

    {:ok, _external_scenes} =
      ExternalScenes.sync_home_assistant_scenes(bridge, [
        %{source_id: "scene.movie_time", name: "Movie Time", metadata: %{}}
      ])

    {:ok, view, html} = live(conn, "/config/bridge/#{bridge.id}/external-scenes")
    assert html =~ "External Scenes"
    assert html =~ "Movie Time"

    external_scene = ExternalScenes.list_external_scenes_for_bridge(bridge.id) |> List.first()

    view
    |> form("div#external-scene-#{external_scene.id} form", %{
      "external_scene_id" => external_scene.id,
      "scene_id" => Integer.to_string(scene.id),
      "enabled" => "true"
    })
    |> render_submit()

    html = render(view)
    assert html =~ "Mapping saved."
    assert html =~ "mapped"
  end
end
