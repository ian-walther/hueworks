defmodule HueworksWeb.HealthControllerTest do
  use HueworksWeb.ConnCase, async: false

  setup do
    previous = Application.get_env(:hueworks, :health_module)
    previous_runtime_io_disabled = Application.get_env(:hueworks, :runtime_io_disabled)

    on_exit(fn ->
      if previous do
        Application.put_env(:hueworks, :health_module, previous)
      else
        Application.delete_env(:hueworks, :health_module)
      end

      restore_app_env(:hueworks, :runtime_io_disabled, previous_runtime_io_disabled)
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

  test "reports an explicitly isolated but ready verification runtime", %{conn: conn} do
    Application.put_env(:hueworks, :runtime_io_disabled, true)

    response = conn |> get("/health") |> json_response(200)

    assert response["status"] == "ok"
    assert response["database"] == "ok"
    assert response["runtime_io"] == "disabled"
    assert response["runtime"]["control_state"] == "ok"
    assert response["runtime"]["desired_state"] == "ok"
    assert response["runtime"]["executor"] == "disabled"
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
