defmodule HueworksWeb.Layouts do
  use Phoenix.Component

  def root(assigns) do
    ~H"""
    <!DOCTYPE html>
    <html lang="en">
      <head>
        <meta charset="utf-8"/>
        <meta name="viewport" content="width=device-width, initial-scale=1"/>
        <meta name="csrf-token" content={Plug.CSRFProtection.get_csrf_token()}/>
        <title>HueWorks</title>
        <link phx-track-static rel="stylesheet" href="/assets/app.css"/>
        <script defer phx-track-static type="text/javascript" src="/assets/app.js"></script>
      </head>
      <body>
        <nav class="hw-nav">
          <div class="hw-nav-inner">
            <div class="hw-nav-title">HueWorks</div>
            <div class="hw-nav-links">
              <a href="/lights">Lights</a>
              <a href="/rooms">Rooms</a>
              <a href="/config">Config</a>
            </div>
          </div>
        </nav>
        <%= @inner_content %>
      </body>
    </html>
    """
  end

  attr :flash, :map, default: nil
  attr :class, :string, default: nil

  def app_flash_group(assigns) do
    ~H"""
    <div
      :if={Phoenix.Flash.get(@flash, :info) || Phoenix.Flash.get(@flash, :error)}
      class={["hw-flash-stack", @class]}
    >
      <div
        :if={message = Phoenix.Flash.get(@flash, :info)}
        id="hw-app-flash-info"
        class="hw-flash-bar hw-flash-bar-info"
        phx-hook="AutoClearFlash"
        data-key="info"
        role="status"
      >
        <span><%= message %></span>
      </div>
      <div
        :if={message = Phoenix.Flash.get(@flash, :error)}
        id="hw-app-flash-error"
        class="hw-flash-bar hw-flash-bar-error"
        phx-hook="AutoClearFlash"
        data-key="error"
        role="alert"
      >
        <span><%= message %></span>
      </div>
    </div>
    """
  end

  attr :flash, :map, default: nil
  attr :info, :string, default: nil
  attr :error, :string, default: nil
  attr :class, :string, default: nil

  def floating_flash_group(assigns) do
    info = assigns.info || (assigns.flash && Phoenix.Flash.get(assigns.flash, :info))
    error = assigns.error || (assigns.flash && Phoenix.Flash.get(assigns.flash, :error))

    assigns =
      assigns
      |> assign(:info_message, info)
      |> assign(:error_message, error)

    ~H"""
    <div
      :if={@info_message || @error_message}
      class={["hw-flash-stack", @class]}
      aria-live="polite"
    >
      <div :if={@info_message} class="hw-flash-bar hw-flash-bar-info" role="status">
        <span><%= @info_message %></span>
      </div>
      <div :if={@error_message} class="hw-flash-bar hw-flash-bar-error" role="alert">
        <span><%= @error_message %></span>
      </div>
    </div>
    """
  end
end
