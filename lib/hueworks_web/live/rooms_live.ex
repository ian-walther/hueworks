defmodule HueworksWeb.RoomsLive do
  use Phoenix.LiveView

  def mount(_params, _session, socket) do
    {:ok, socket}
  end

  def render(assigns) do
    ~H"""
    <div class="hw-shell">
      <div class="hw-topbar">
        <div>
          <h1 class="hw-title">Rooms</h1>
          <p class="hw-subtitle">Room management UI coming soon.</p>
        </div>
      </div>
    </div>
    """
  end
end
