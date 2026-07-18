defmodule HueworksWeb.Layouts do
  use Phoenix.Component

  def root(assigns) do
    assigns = assign(assigns, :current_path, current_path(assigns))

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
              <a href="/control" class={nav_class(@current_path, "/control")} aria-current={nav_current(@current_path, "/control")}>Control</a>
              <a href="/lights" class={nav_class(@current_path, "/lights")} aria-current={nav_current(@current_path, "/lights")}>Lights</a>
              <a href="/areas" class={nav_class(@current_path, "/areas")} aria-current={nav_current(@current_path, "/areas")}>Areas</a>
              <a href="/config" class={nav_class(@current_path, "/config")} aria-current={nav_current(@current_path, "/config")}>Config</a>
            </div>
          </div>
        </nav>
        <%= @inner_content %>
      </body>
    </html>
    """
  end

  defp current_path(%{conn: %{request_path: path}}), do: path
  defp current_path(_assigns), do: ""

  defp nav_class(path, root) do
    ["hw-nav-link", String.starts_with?(path, root) && "hw-nav-link-active"]
  end

  defp nav_current(path, root) do
    if String.starts_with?(path, root), do: "page"
  end

  attr(:flash, :map, default: nil)
  attr(:class, :string, default: nil)

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
end
