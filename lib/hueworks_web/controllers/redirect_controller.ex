defmodule HueworksWeb.RedirectController do
  use Phoenix.Controller

  def home(conn, _params) do
    redirect(conn, to: "/lights")
  end
end
