defmodule Hueworks.HomeKit do
  @moduledoc false

  alias Hueworks.HomeKit.Bridge

  def reload, do: Bridge.reload()
  def put_change_token(opts, change_token), do: Bridge.put_change_token(opts, change_token)
end
