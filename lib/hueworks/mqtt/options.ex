defmodule Hueworks.Mqtt.Options do
  @moduledoc false

  def put_auth(opts, %{username: username, password: password}) when is_list(opts) do
    if is_binary(username) do
      opts
      |> Keyword.put(:user_name, username)
      |> maybe_put_password(password)
    else
      opts
    end
  end

  def put_auth(opts, _config) when is_list(opts), do: opts

  defp maybe_put_password(opts, password) when is_binary(password),
    do: Keyword.put(opts, :password, password)

  defp maybe_put_password(opts, _password), do: opts
end
