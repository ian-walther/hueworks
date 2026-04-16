defmodule Hueworks.HomeAssistant.Export.ServerState do
  @moduledoc false

  @enforce_keys [:config, :connection_pid]
  defstruct [:config, :connection_pid]

  def new do
    %__MODULE__{config: nil, connection_pid: nil}
  end
end
