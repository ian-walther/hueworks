defmodule Hueworks.Import.PipelineTest do
  use Hueworks.DataCase, async: false

  alias Hueworks.Import.Pipeline
  alias Hueworks.Repo
  alias Hueworks.Schemas.{Bridge, BridgeImport}

  test "fetch_raw returns an error for unsupported bridge types" do
    bridge = %Bridge{type: :unsupported, name: "Mystery", host: "10.0.0.10", credentials: nil}

    assert {:error, message} = Pipeline.fetch_raw(bridge)
    assert message =~ "no function clause"
  end

  test "fetch_raw returns an error when Home Assistant credentials are missing" do
    bridge =
      %Bridge{}
      |> Bridge.changeset(%{
        type: :ha,
        name: "Home Assistant",
        host: "10.0.0.20",
        credentials: %{"token" => ""},
        enabled: true,
        import_complete: false
      })
      |> Repo.insert!()

    assert {:error, message} = Pipeline.fetch_raw(bridge)
    assert message =~ "Missing Home Assistant token"
  end

  test "fetch_raw returns an error when Hue credentials are missing" do
    bridge =
      %Bridge{}
      |> Bridge.changeset(%{
        type: :hue,
        name: "Hue Bridge",
        host: "10.0.0.22",
        credentials: %{"api_key" => ""},
        enabled: true,
        import_complete: false
      })
      |> Repo.insert!()

    assert {:error, message} = Pipeline.fetch_raw(bridge)
    assert message =~ "Missing Hue api_key"
  end

  test "create_import returns an error and does not persist a bridge import when fetch fails" do
    bridge =
      %Bridge{}
      |> Bridge.changeset(%{
        type: :ha,
        name: "Home Assistant",
        host: "10.0.0.21",
        credentials: %{"token" => ""},
        enabled: true,
        import_complete: false
      })
      |> Repo.insert!()

    assert {:error, message} = Pipeline.create_import(bridge)
    assert message =~ "Missing Home Assistant token"
    assert Repo.aggregate(BridgeImport, :count) == 0
  end
end
