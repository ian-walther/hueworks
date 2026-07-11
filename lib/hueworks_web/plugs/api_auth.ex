defmodule HueworksWeb.Plugs.ApiAuth do
  @moduledoc false

  import Plug.Conn

  alias Hueworks.AppSettings
  alias HueworksWeb.Api.Response

  def init(opts), do: opts

  def call(conn, _opts) do
    cond do
      not AppSettings.api_enabled?() ->
        Response.error(conn, 404, "api_disabled", "AI API access is disabled.")
        |> halt()

      valid_bearer_token?(conn) ->
        conn

      true ->
        Response.error(conn, 401, "unauthorized", "A valid bearer token is required.")
        |> halt()
    end
  end

  defp valid_bearer_token?(conn) do
    with [authorization] <- get_req_header(conn, "authorization"),
         "Bearer " <> supplied_token <- authorization,
         expected_token when is_binary(expected_token) <- AppSettings.api_token(),
         true <- byte_size(expected_token) == byte_size(supplied_token) do
      Plug.Crypto.secure_compare(expected_token, supplied_token)
    else
      _ -> false
    end
  end
end
