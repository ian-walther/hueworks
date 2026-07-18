defmodule Hueworks.HomeKit do
  @moduledoc false

  alias Hueworks.AppSettings
  alias Hueworks.HomeKit.Bridge
  alias Hueworks.HomeKit.Config
  alias Hueworks.HomeKit.PairingState

  def reload, do: Bridge.reload()
  def put_change_token(opts, change_token), do: Bridge.put_change_token(opts, change_token)

  def runtime_status do
    if Application.get_env(:hueworks, :homekit_runtime_enabled, true) do
      case Bridge.status() do
        %{running?: true} -> :running
        _status -> :unavailable
      end
    else
      :disabled
    end
  end

  def paired? do
    current_config()
    |> Map.fetch!(:data_path)
    |> pairing_state_module().paired?()
  end

  def reset_pairings do
    data_path =
      current_config()
      |> Map.fetch!(:data_path)

    with {:ok, count} <- pairing_state_module().clear_pairings(data_path) do
      Bridge.reload()
      {:ok, count}
    end
  end

  defp pairing_state_module do
    Application.get_env(:hueworks, :homekit_pairing_state_module, PairingState)
  end

  defp current_config do
    AppSettings.get_global()
    |> Config.from_settings()
  end
end
