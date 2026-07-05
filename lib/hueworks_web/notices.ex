defmodule HueworksWeb.Notices do
  @moduledoc false

  import Phoenix.Component, only: [assign: 3]

  def maybe_put_status_flash(socket) do
    case socket.assigns[:status] do
      status when is_binary(status) ->
        socket
        |> assign(:status, nil)
        |> put_notice(:info, status)

      _ ->
        socket
    end
  end

  def put_notice(socket, :info, message) when is_binary(message) do
    socket
    |> Phoenix.LiveView.clear_flash(:error)
    |> Phoenix.LiveView.put_flash(:info, message)
  end

  def put_notice(socket, :error, message) when is_binary(message) do
    socket
    |> Phoenix.LiveView.clear_flash(:info)
    |> Phoenix.LiveView.put_flash(:error, message)
  end
end
