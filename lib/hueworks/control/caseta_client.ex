defmodule Hueworks.Control.CasetaClient do
  @moduledoc false

  alias Hueworks.Control.CasetaLeap

  @bridge_port 8081

  def request(host, ssl_opts, payload, ssl_module \\ :ssl) do
    with {:ok, socket} <-
           ssl_module.connect(String.to_charlist(host), @bridge_port, ssl_opts, 5000) do
      result = request_on_socket(ssl_module, socket, payload)
      ssl_module.close(socket)
      result
    else
      {:error, reason} -> {:error, reason}
    end
  end

  defp request_on_socket(ssl_module, socket, payload) do
    with :ok <- CasetaLeap.set_socket_opts(ssl_module, socket),
         :ok <- CasetaLeap.send_request(ssl_module, socket, payload) do
      payload
      |> get_in(["Header", "Url"])
      |> then(&CasetaLeap.read_until_match(ssl_module, socket, &1, 5000, :status))
    end
  end
end
