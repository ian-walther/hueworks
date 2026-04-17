defmodule HueworksWeb.ExternalSceneConfigLiveTest do
  use HueworksWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Hueworks.ExternalScenes
  alias Hueworks.Repo
  alias Hueworks.Schemas.Room
  alias Hueworks.Scenes

  test "non-Home Assistant bridges redirect back to config", %{conn: conn} do
    bridge =
      insert_bridge!(%{
        type: :hue,
        name: "Hue Bridge",
        host: "10.0.0.90",
        credentials: %{"api_key" => "key"},
        enabled: true,
        import_complete: true
      })

    assert {:error, {:live_redirect, %{to: "/config"}}} =
             live(conn, "/config/bridge/#{bridge.id}/external-scenes")
  end

  test "scene config page syncs HA scenes and saves mappings", %{conn: conn} do
    bridge =
      insert_bridge!(%{
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
    refute html =~ "Mapping saved."

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

  test "sync errors are shown on the page", %{conn: conn} do
    bridge =
      insert_bridge!(%{
        type: :ha,
        name: "Home Assistant",
        host: "10.0.0.91",
        credentials: %{},
        enabled: true,
        import_complete: true
      })

    {:ok, view, html} = live(conn, "/config/bridge/#{bridge.id}/external-scenes")
    assert html =~ "External Scenes"
    refute html =~ "Missing Home Assistant token"

    html =
      view
      |> element("button[phx-click='sync_external_scenes']")
      |> render_click()

    assert html =~ "Missing Home Assistant token"
  end

  test "save_mapping reports missing external scenes", %{conn: conn} do
    bridge =
      insert_bridge!(%{
        type: :ha,
        name: "Home Assistant",
        host: "10.0.0.91",
        credentials: %{"token" => "token"},
        enabled: true,
        import_complete: true
      })

    {:ok, view, html} = live(conn, "/config/bridge/#{bridge.id}/external-scenes")
    assert html =~ "External Scenes"

    html =
      render_submit(view, "save_mapping", %{
        "external_scene_id" => "-1",
        "scene_id" => "",
        "enabled" => "true"
      })

    assert html =~ "External scene not found."
  end
end
