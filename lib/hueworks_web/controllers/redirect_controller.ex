defmodule HueworksWeb.RedirectController do
  use Phoenix.Controller

  alias Hueworks.{Bridges, Onboarding}

  def home(conn, _params) do
    path =
      cond do
        Onboarding.status().auto_open? -> "/setup"
        Bridges.any_bridges?() -> "/control"
        true -> "/config"
      end

    redirect(conn, to: path)
  end
end
