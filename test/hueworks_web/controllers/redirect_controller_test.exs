defmodule HueworksWeb.RedirectControllerTest do
  use HueworksWeb.ConnCase, async: false

  alias Hueworks.{Onboarding, Repo}
  alias Hueworks.Schemas.Bridge

  test "an untouched installation routes to dedicated first-run setup", %{conn: conn} do
    conn = get(conn, "/")

    assert redirected_to(conn) == "/setup"
  end

  test "an explicitly dismissed empty setup routes to config", %{conn: conn} do
    assert {:ok, _settings} = Onboarding.dismiss()

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
