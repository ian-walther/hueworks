defmodule HueworksWeb.ConfigComponents do
  use Phoenix.Component

  attr(:active, :atom, required: true)
  attr(:title, :string, required: true)
  attr(:subtitle, :string, default: nil)
  attr(:breadcrumbs, :list, default: [])
  attr(:flash, :map, default: nil)
  slot(:actions)
  slot(:inner_block, required: true)

  def page(assigns) do
    ~H"""
    <div class="hw-config-page">
      <.section_nav active={@active} />

      <HueworksWeb.PageComponents.page
        class="hw-config-shell hw-config-content-frame"
        eyebrow="Configuration"
        title={@title}
        subtitle={@subtitle}
        flash={@flash}
      >
        <:preamble>
          <.breadcrumbs :if={@breadcrumbs != []} items={@breadcrumbs} />
        </:preamble>
        <:actions :if={@actions != []}>
          <%= render_slot(@actions) %>
        </:actions>
        <%= render_slot(@inner_block) %>
      </HueworksWeb.PageComponents.page>
    </div>
    """
  end

  attr(:active, :atom, required: true)

  def section_nav(assigns) do
    assigns =
      assign(assigns, :items, [
        {:overview, "Overview", "/config"},
        {:general, "General", "/config/general"},
        {:bridges, "Bridges", "/config/bridges"},
        {:light_states, "Light States", "/config/light-states"},
        {:integrations, "Integrations", "/config/integrations"}
      ])

    ~H"""
    <nav class="hw-config-nav" aria-label="Configuration sections">
      <div class="hw-config-nav-inner hw-content-frame hw-config-content-frame">
        <a
          :for={{key, label, path} <- @items}
          href={path}
          class={["hw-config-nav-link", @active == key && "hw-config-nav-link-active"]}
          aria-current={if @active == key, do: "page"}
        >
          <%= label %>
        </a>
      </div>
    </nav>
    """
  end

  attr(:items, :list, required: true)

  def breadcrumbs(assigns) do
    ~H"""
    <nav class="hw-breadcrumbs" aria-label="Breadcrumb">
      <ol>
        <li :for={{item, index} <- Enum.with_index(@items)}>
          <span :if={index > 0} class="hw-breadcrumb-separator" aria-hidden="true">/</span>
          <a :if={item[:to]} href={item.to}><%= item.label %></a>
          <span :if={!item[:to]} aria-current="page"><%= item.label %></span>
        </li>
      </ol>
    </nav>
    """
  end

  attr(:title, :string, required: true)
  attr(:description, :string, required: true)
  attr(:href, :string, required: true)
  attr(:status, :string, required: true)
  attr(:tone, :atom, default: :quiet)
  slot(:detail)

  def overview_card(assigns) do
    ~H"""
    <a class="hw-config-overview-card" href={@href}>
      <div class="hw-config-overview-card-header">
        <h2><%= @title %></h2>
        <span class={["hw-status-badge", "hw-status-badge-#{@tone}"]}><%= @status %></span>
      </div>
      <p><%= @description %></p>
      <div :if={@detail != []} class="hw-config-overview-detail"><%= render_slot(@detail) %></div>
      <span class="hw-config-overview-link">Open <span aria-hidden="true">→</span></span>
    </a>
    """
  end
end
