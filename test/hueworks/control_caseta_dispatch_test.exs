defmodule Hueworks.Control.CasetaDispatchTest do
  use Hueworks.DataCase, async: false

  alias Hueworks.Repo
  alias Hueworks.Schemas.{Bridge, Light, Area}

  test "empty desired state does not open a Caseta connection" do
    area = Repo.insert!(%Area{name: "No-op"})

    bridge =
      %Bridge{}
      |> Bridge.changeset(%{
        type: :caseta,
        name: "Caseta",
        host: "127.0.0.1",
        credentials: %{
          "cert_path" => "/nonexistent/client.crt",
          "key_path" => "/nonexistent/client.key",
          "cacert_path" => "/nonexistent/caseta.crt"
        },
        enabled: true
      })
      |> Repo.insert!()

    light =
      Repo.insert!(%Light{
        name: "No-op Caseta Light",
        source: :caseta,
        source_id: "1",
        bridge_id: bridge.id,
        area_id: area.id
      })

    assert :ok = Hueworks.Control.Light.dispatch_state(light, %{})
  end
end
