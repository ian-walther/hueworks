defmodule HueworksWeb.Router do
  use Phoenix.Router
  import Phoenix.LiveView.Router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug HueworksWeb.Plugs.SessionId
    plug :put_root_layout, html: {HueworksWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  scope "/", HueworksWeb do
    pipe_through :browser

    get "/", RedirectController, :home
    live "/lights", LightsLive, :index
    live "/rooms", RoomsLive, :index
    live "/explore", ExplorationLive, :index
  end
end
