defmodule HueworksWeb.PageComponents do
  use Phoenix.Component

  attr(:eyebrow, :string, required: true)
  attr(:title, :string, required: true)
  attr(:subtitle, :string, default: nil)
  slot(:actions)

  def header(assigns) do
    ~H"""
    <header class="hw-page-header">
      <div>
        <p class="hw-eyebrow"><%= @eyebrow %></p>
        <h1 class="hw-title"><%= @title %></h1>
        <p :if={@subtitle} class="hw-subtitle"><%= @subtitle %></p>
      </div>
      <div :if={@actions != []} class="hw-page-actions">
        <%= render_slot(@actions) %>
      </div>
    </header>
    """
  end
end
