defmodule HueworksWeb.RedirectController do
  use Phoenix.Controller

  alias Hueworks.Bridges

  def home(conn, _params) do
    redirect(conn, to: if(Bridges.any_bridges?(), do: "/control", else: "/config"))
  end
end
