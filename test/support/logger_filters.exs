defmodule Hueworks.TestLogFilter do
  @moduledoc false

  def suppress_exqlite_client_exits(%{level: :error, msg: msg} = event, _extra) do
    message = message_to_string(msg)

    if String.contains?(message, "Exqlite.Connection") and
         String.contains?(message, "disconnected: ** (DBConnection.ConnectionError) client #PID<") and
         String.contains?(message, " exited") do
      :stop
    else
      event
    end
  end

  def suppress_exqlite_client_exits(event, _extra), do: event

  defp message_to_string({:string, message}) when is_binary(message), do: message
  defp message_to_string({:string, message}), do: IO.chardata_to_string(message)
  defp message_to_string(message) when is_binary(message), do: message
  defp message_to_string(message), do: inspect(message)
end
