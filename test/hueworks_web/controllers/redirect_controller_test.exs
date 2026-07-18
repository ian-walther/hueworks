defmodule HueworksWeb.RedirectControllerTest do
  use HueworksWeb.ConnCase, async: false

  alias Hueworks.Repo
  alias Hueworks.Schemas.Bridge

  test "an empty installation routes to first-run configuration", %{conn: conn} do
    conn = get(conn, "/")

    assert redirected_to(conn) == "/config"
  end

  test "an installation with a bridge routes to daily control", %{conn: conn} do
    Repo.insert!(%Bridge{
      type: :hue,
      name: "Hue Bridge",
      host: "192.0.2.10",
      credentials: %Bridge.Credentials{api_key: "test-key"}
    })

    conn = get(conn, "/")

    assert redirected_to(conn) == "/control"
  end
end
