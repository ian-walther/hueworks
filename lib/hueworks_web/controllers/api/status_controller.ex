defmodule HueworksWeb.Api.StatusController do
  use Phoenix.Controller

  alias Hueworks.Api
  alias HueworksWeb.Api.Response

  def show(conn, _params) do
    Response.ok(conn, Api.status())
  end
end
