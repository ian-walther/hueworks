defmodule Hueworks.HomeAssistant.Export.ServerState do
  @moduledoc false

  @enforce_keys [:config, :connection_pid, :settings_session]
  defstruct [:config, :connection_pid, :settings_session]

  def new do
    %__MODULE__{config: nil, connection_pid: nil, settings_session: nil}
  end
end
