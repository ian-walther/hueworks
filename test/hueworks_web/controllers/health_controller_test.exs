defmodule HueworksWeb.HealthControllerTest do
  use HueworksWeb.ConnCase, async: false

  setup do
    previous = Application.get_env(:hueworks, :health_module)

    on_exit(fn ->
      if previous do
        Application.put_env(:hueworks, :health_module, previous)
      else
        Application.delete_env(:hueworks, :health_module)
      end
    end)

    :ok
  end

  test "reports non-sensitive readiness without API authentication", %{conn: conn} do
    response = conn |> get("/health") |> json_response(200)

    assert response == %{
             "status" => "ok",
             "version" => "0.1.0",
             "database" => "ok",
             "runtime" => %{
               "control_state" => "ok",
               "desired_state" => "ok",
               "executor" => "ok"
             }
           }

    refute inspect(response) =~ "token"
    refute inspect(response) =~ "host"
  end

  test "returns service unavailable when readiness fails", %{conn: conn} do
    Application.put_env(:hueworks, :health_module, __MODULE__.UnavailableHealth)

    assert %{"status" => "unavailable", "database" => "error"} =
             conn |> get("/health") |> json_response(503)
  end

  defmodule UnavailableHealth do
    def status do
      %{
        ready?: false,
        body: %{
          status: "unavailable",
          version: "0.1.0",
          database: "error",
          runtime: %{}
        }
      }
    end
  end
end
