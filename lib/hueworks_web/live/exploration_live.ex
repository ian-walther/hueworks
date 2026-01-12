defmodule HueworksWeb.ExplorationLive do
  use Phoenix.LiveView

  def mount(_params, _session, socket) do
    {:ok, assign(socket, status: "Ready for exploration")}
  end

  def render(assigns) do
    ~H"""
    <div class="p-8">
      <h1 class="text-2xl font-bold mb-4">HueWorks Exploration UI</h1>

      <div class="mb-8">
        <h2 class="text-xl font-semibold mb-2">Phase 0: Vertical Slice Exploration</h2>
        <p class="text-gray-600">
          Manual control buttons and API testing will be added here during exploration.
        </p>
      </div>

      <%= if @status do %>
        <div class="mt-4 p-4 bg-blue-50 border border-blue-200 rounded">
          <%= @status %>
        </div>
      <% end %>
    </div>
    """
  end
end
