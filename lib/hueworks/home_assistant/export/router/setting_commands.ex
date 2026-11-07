defmodule Hueworks.HomeAssistant.Export.Router.SettingCommands do
  @moduledoc false

  require Logger

  alias Hueworks.AppSettings
  alias Hueworks.HomeAssistant.Export.Commands
  alias Hueworks.HomeAssistant.Export.Publisher
  alias Hueworks.HomeAssistant.Export.ServerState

  def handle_command(field, payload, %ServerState{} = state, publish_fun)
      when is_atom(field) and is_function(publish_fun, 3) do
    with {:ok, value} <- command_value(payload, state.settings_session),
         {:ok, _settings} <- AppSettings.upsert_global(%{field => value}) do
      :ok
    else
      {:error, reason} ->
        Logger.warning(
          "HA export setting command ignored field=#{field} reason=#{describe_error(reason)}"
        )
    end

    # Home Assistant shows only what HueWorks accepted, whatever became of the command.
    Publisher.publish_setting_state(
      publish_fun,
      field,
      Map.fetch!(AppSettings.get_global(), field)
    )
  end

  defp command_value(payload, session) do
    case Commands.decode_json_payload(payload) do
      {:ok, %{"session" => ^session, "value" => value}}
      when is_binary(session) and (is_binary(value) or is_nil(value)) ->
        {:ok, value}

      {:ok, %{"session" => other, "value" => _value}} when other != session ->
        {:error, :stale_session}

      _ ->
        {:error, :malformed_payload}
    end
  end

  defp describe_error(%Ecto.Changeset{} = changeset) do
    changeset
    |> Hueworks.Util.changeset_errors()
    |> Enum.map_join(", ", fn {field, message} -> "#{field} #{message}" end)
  end

  defp describe_error(reason), do: inspect(reason)
end
