defmodule Hueworks.HomeAssistant.Export.Lifecycle do
  @moduledoc false

  alias Hueworks.HomeAssistant.Export.Lifecycle.ConfigTransition
  alias Hueworks.HomeAssistant.Export.Lifecycle.SyncDispatch

  defdelegate configure(state, config, client_id, publish_fun), to: ConfigTransition
  defdelegate handle_cast(message, state, publish_fun), to: SyncDispatch
  defdelegate handle_connected(connection_client_id, state, client_id, publish_fun), to: SyncDispatch
  defdelegate handle_control_state(kind, id, state, publish_fun), to: SyncDispatch
end
