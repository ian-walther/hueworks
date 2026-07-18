defmodule HueworksWeb.HealthController do
  use Phoenix.Controller

  def show(conn, _params) do
    %{ready?: ready?, body: body} = health_module().status()

    conn
    |> put_status(if(ready?, do: :ok, else: :service_unavailable))
    |> json(body)
  end

  defp health_module do
    Application.get_env(:hueworks, :health_module, Hueworks.Health)
  end
end
