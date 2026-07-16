defmodule HueworksWeb.PageComponents do
  use Phoenix.Component

  attr(:eyebrow, :string, required: true)
  attr(:title, :string, required: true)
  attr(:subtitle, :string, default: nil)
  attr(:flash, :map, default: nil)
  attr(:class, :any, default: nil)
  slot(:preamble)
  slot(:actions)
  slot(:inner_block, required: true)

  def page(assigns) do
    ~H"""
    <main class={["hw-shell hw-content-frame hw-page", @class]}>
      <%= render_slot(@preamble) %>

      <.header eyebrow={@eyebrow} title={@title} subtitle={@subtitle}>
        <:actions :if={@actions != []}>
          <%= render_slot(@actions) %>
        </:actions>
      </.header>

      <HueworksWeb.Layouts.app_flash_group flash={@flash} class="hw-flash-stack-inline" />
      <%= render_slot(@inner_block) %>
    </main>
    """
  end

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
