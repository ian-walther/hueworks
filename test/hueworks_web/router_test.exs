defmodule HueworksWeb.RouterTest do
  use HueworksWeb.ConnCase, async: true

  test "router exposes the current primary browser routes and not stale exploration" do
    paths =
      HueworksWeb.Router
      |> Phoenix.Router.routes()
      |> Enum.map(& &1.path)

    assert "/" in paths
    assert "/control" in paths
    assert "/lights" in paths
    assert "/rooms" in paths
    assert "/config" in paths
    assert "/config/light-states/:id/edit" in paths
    assert "/config/bridge/:id/picos/:pico_id" in paths

    refute "/explore" in paths
  end
end
