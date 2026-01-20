defmodule HueworksWeb.ConfigLive do
  use Phoenix.LiveView

  def mount(_params, _session, socket) do
    bridges = Hueworks.Repo.all(Hueworks.Schemas.Bridge)
    {:ok, assign(socket, bridges: bridges)}
  end

  def handle_event("noop", _params, socket) do
    {:noreply, socket}
  end

end
