defmodule HueworksWeb.Router do
  use Phoenix.Router
  import Phoenix.LiveView.Router

  pipeline :browser do
    plug(:accepts, ["html"])
    plug(:fetch_session)
    plug(:fetch_live_flash)
    plug(HueworksWeb.Plugs.SessionId)
    plug(:put_root_layout, html: {HueworksWeb.Layouts, :root})
    plug(:protect_from_forgery)
    plug(:put_secure_browser_headers)
  end

  pipeline :api do
    plug(:accepts, ["json"])
    plug(HueworksWeb.Plugs.ApiAuth)
  end

  scope "/", HueworksWeb do
    pipe_through(:browser)

    get("/", RedirectController, :home)
    live("/control", ControlLive, :index)
    live("/lights", LightsLive, :index)
    live("/rooms", RoomsLive, :index)
    live("/rooms/:room_id/scenes/new", SceneEditorLive, :new)
    live("/rooms/:room_id/scenes/:id/edit", SceneEditorLive, :edit)
    live("/config", ConfigLive, :index)
    live("/config/general", GeneralConfigLive, :index)
    live("/config/bridges", BridgesConfigLive, :index)
    live("/config/light-states", LightStatesConfigLive, :index)
    live("/config/integrations", IntegrationsConfigLive, :index)
    live("/config/light-states/new/manual", LightStateEditorLive, :new_manual)
    live("/config/light-states/new/circadian", LightStateEditorLive, :new_circadian)
    live("/config/light-states/:id/edit", LightStateEditorLive, :edit)
    live("/config/bridges/new", BridgeLive, :index)
    live("/config/bridges/:id/import", BridgeSetupLive, :import)
    live("/config/bridges/:id/reimport", BridgeReimportLive, :index)
    live("/config/bridges/:id/picos", PicoConfigLive, :index)
    live("/config/bridges/:id/picos/:pico_id", PicoConfigLive, :show)
    live("/config/bridges/:id/external-scenes", ExternalSceneConfigLive, :index)
  end

  scope "/api/v1", HueworksWeb.Api do
    pipe_through(:api)

    get("/status", StatusController, :show)
    get("/rooms", RoomsController, :index)
    get("/rooms/:id", RoomsController, :show)
    get("/entities", EntitiesController, :search)
    get("/lights/:id", EntitiesController, :show_light)
    get("/groups/:id", EntitiesController, :show_group)
    get("/traces", TracesController, :index)
    get("/debug/rooms/:id", RoomsController, :debug)
    get("/debug/lights/:id", EntitiesController, :debug_light)
    get("/debug/groups/:id", EntitiesController, :debug_group)
    post("/scenes/:id/activate", ControlsController, :activate_scene)
    delete("/rooms/:id/active-scene", ControlsController, :deactivate_room_scene)
    post("/lights/:id/control", ControlsController, :control_light)
    post("/groups/:id/control", ControlsController, :control_group)
    post("/runtime/physical-state/refresh", ControlsController, :refresh_physical_state)
  end
end
