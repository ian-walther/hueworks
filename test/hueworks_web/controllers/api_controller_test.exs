defmodule HueworksWeb.ApiControllerTest do
  use HueworksWeb.ConnCase, async: false

  alias Hueworks.ActiveScenes
  alias Hueworks.AppSettings
  alias Hueworks.Control.{DesiredState, State, TraceBuffer}
  alias Hueworks.Repo
  alias Hueworks.Schemas.{Bridge, Group, GroupLight, Light, Area, Scene}

  setup do
    TraceBuffer.clear()
    assert {:ok, _settings} = AppSettings.enable_api_access()
    %{token: AppSettings.api_token()}
  end

  test "rejects missing or invalid bearer credentials", %{conn: conn} do
    assert %{"error" => %{"code" => "unauthorized"}} =
             conn
             |> get("/api/v1/status")
             |> json_response(401)

    assert %{"error" => %{"code" => "unauthorized"}} =
             conn
             |> put_req_header("authorization", "Bearer wrong-token")
             |> get("/api/v1/status")
             |> json_response(401)
  end

  test "treats disabled API access as unavailable", %{conn: conn, token: token} do
    assert {:ok, _settings} = AppSettings.disable_api_access()

    assert %{"error" => %{"code" => "api_disabled"}} =
             conn
             |> api_auth(token)
             |> get("/api/v1/status")
             |> json_response(404)
  end

  test "immediately rejects a bearer token after it is rotated", %{
    conn: conn,
    token: previous_token
  } do
    assert {:ok, _settings} = AppSettings.rotate_api_token()
    current_token = AppSettings.api_token()
    refute current_token == previous_token

    assert %{"error" => %{"code" => "unauthorized"}} =
             conn
             |> api_auth(previous_token)
             |> get("/api/v1/status")
             |> json_response(401)

    assert %{"api_version" => "v1"} =
             build_conn()
             |> api_auth(current_token)
             |> get("/api/v1/status")
             |> json_response(200)
  end

  test "serializes concise state without the configured API token or bridge credentials", %{
    conn: conn,
    token: token
  } do
    %{area: area, light: light} = fixture()
    _ = State.put(:light, light.id, %{power: :on, brightness: 64})
    _ = DesiredState.put(:light, light.id, %{power: :on, brightness: 65})

    status_response =
      conn
      |> api_auth(token)
      |> get("/api/v1/status")
      |> json_response(200)

    assert status_response["api_version"] == "v1"
    refute inspect(status_response) =~ token

    area_response =
      build_conn()
      |> api_auth(token)
      |> get("/api/v1/areas/#{area.id}")
      |> json_response(200)

    assert area_response["kind"] == "area"

    assert [%{"id" => area_light_id, "physical_state" => %{"power" => "on"}}] =
             area_response["lights"]

    assert area_light_id == light.id

    light_response =
      build_conn()
      |> api_auth(token)
      |> get("/api/v1/lights/#{light.id}")
      |> json_response(200)

    assert light_response["desired_state"] == %{"power" => "on", "brightness" => 65}
    refute inspect(light_response) =~ "controller-bridge-secret"
    refute Map.has_key?(light_response, "metadata")
  end

  test "validates trace query filters and returns structured trace records", %{
    conn: conn,
    token: token
  } do
    TraceBuffer.record(
      %{trace_id: "api-controller-trace", source: "api.test", area_id: 7},
      :planned,
      %{type: :light, id: 8, desired: %{power: :on}}
    )

    assert %{"error" => %{"code" => "invalid_parameter"}} =
             conn
             |> api_auth(token)
             |> get("/api/v1/traces?limit=lots")
             |> json_response(400)

    assert %{"events" => [%{"trace_id" => "api-controller-trace", "stage" => "planned"}]} =
             build_conn()
             |> api_auth(token)
             |> get("/api/v1/traces?entity_kind=light&entity_id=8")
             |> json_response(200)
  end

  test "searches entities by name and validates lookup filters", %{conn: conn, token: token} do
    %{area: area, light: light, group: group} = fixture()

    assert %{
             "query" => "controller",
             "exact_match_count" => 0,
             "exact_controllable_match_count" => 0,
             "results" => [
               %{
                 "id" => group_id,
                 "kind" => "group",
                 "match" => "prefix",
                 "area_name" => "Controller Area"
               },
               %{
                 "id" => light_id,
                 "kind" => "light",
                 "match" => "prefix",
                 "area_name" => "Controller Area"
               }
             ]
           } =
             conn
             |> api_auth(token)
             |> get("/api/v1/entities?query=controller&area_id=#{area.id}")
             |> json_response(200)

    assert light_id == light.id
    assert group_id == group.id

    for path <- [
          "/api/v1/entities",
          "/api/v1/entities?query=",
          "/api/v1/entities?query=controller&kind=area",
          "/api/v1/entities?query=controller&area_id=zero",
          "/api/v1/entities?query=controller&limit=101"
        ] do
      assert %{"error" => %{"code" => "invalid_parameter"}} =
               build_conn()
               |> api_auth(token)
               |> get(path)
               |> json_response(400)
    end
  end

  test "accepts explicit controls through the normal control path and translates validation errors",
       %{
         conn: conn,
         token: token
       } do
    %{light: light} = fixture()
    _ = State.put(:light, light.id, %{power: :off})

    assert %{
             "operation" => "light_control",
             "target" => %{"kind" => "light", "id" => light_id},
             "accepted_intent" => %{"power" => "on"},
             "trace_id" => trace_id,
             "plan" => %{"action_count" => 1}
           } =
             conn
             |> api_auth(token)
             |> post("/api/v1/lights/#{light.id}/control", %{"power" => "on"})
             |> json_response(200)

    assert light_id == light.id
    assert is_binary(trace_id)
    assert DesiredState.get(:light, light.id).power == :on

    assert %{"error" => %{"code" => "invalid_control"}} =
             build_conn()
             |> api_auth(token)
             |> post("/api/v1/lights/#{light.id}/control", %{"power" => "on", "brightness" => 50})
             |> json_response(422)
  end

  test "activates and deactivates scenes explicitly, never through a toggle endpoint", %{
    conn: conn,
    token: token
  } do
    %{area: area} = fixture()
    scene = Repo.insert!(%Scene{name: "Controller Scene", area_id: area.id})

    assert %{"operation" => "scene_activate", "trace_id" => trace_id} =
             conn
             |> api_auth(token)
             |> post("/api/v1/scenes/#{scene.id}/activate", %{})
             |> json_response(200)

    assert is_binary(trace_id)
    assert ActiveScenes.get_for_area(area.id).scene_id == scene.id

    assert %{"operation" => "area_scene_deactivate", "target" => %{"id" => area_id}} =
             build_conn()
             |> api_auth(token)
             |> delete("/api/v1/areas/#{area.id}/active-scene")
             |> json_response(200)

    assert area_id == area.id
    assert ActiveScenes.get_for_area(area.id) == nil
  end

  test "starts physical-state refresh without waiting for bridge I/O", %{conn: conn, token: token} do
    original_modules = Application.get_env(:hueworks, :control_state_bootstrap_modules)
    Application.put_env(:hueworks, :control_state_bootstrap_modules, [])

    on_exit(fn ->
      restore_app_env(:hueworks, :control_state_bootstrap_modules, original_modules)
    end)

    assert %{"operation" => "physical_state_refresh", "trace_id" => trace_id} =
             conn
             |> api_auth(token)
             |> post("/api/v1/runtime/physical-state/refresh", %{})
             |> json_response(202)

    assert is_binary(trace_id)
  end

  defp api_auth(conn, token) do
    put_req_header(conn, "authorization", "Bearer #{token}")
  end

  defp fixture do
    area = Repo.insert!(%Area{name: "Controller Area"})

    bridge =
      %Bridge{}
      |> Bridge.changeset(%{
        name: "Controller Bridge",
        type: :hue,
        host: "controller-bridge",
        credentials: %{api_key: "controller-bridge-secret"}
      })
      |> Repo.insert!()

    light =
      Repo.insert!(%Light{
        name: "Controller Light",
        display_name: "Controller Light",
        source: :hue,
        source_id: "controller-light",
        bridge_id: bridge.id,
        area_id: area.id
      })

    group =
      Repo.insert!(%Group{
        name: "Controller Group",
        display_name: "Controller Group",
        source: :hue,
        source_id: "controller-group",
        bridge_id: bridge.id,
        area_id: area.id
      })

    Repo.insert!(%GroupLight{group_id: group.id, light_id: light.id})
    %{area: area, light: light, group: group}
  end
end
