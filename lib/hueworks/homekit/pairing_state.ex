defmodule Hueworks.HomeKit.PairingState do
  @moduledoc false

  def paired?(data_path) when is_binary(data_path) do
    cond do
      Process.whereis(HAP.AccessoryServerManager) ->
        HAP.AccessoryServerManager.paired?()

      Process.whereis(HAP.PersistentStorage) ->
        HAP.PersistentStorage.get(:pairings, %{}) != %{}

      true ->
        persisted_pairings?(data_path)
    end
  catch
    :exit, _reason -> false
  end

  def paired?(_data_path), do: false

  def clear_pairings(data_path) when is_binary(data_path) do
    cond do
      Process.whereis(HAP.AccessoryServerManager) ->
        clear_running_manager_pairings()

      Process.whereis(HAP.PersistentStorage) ->
        clear_running_storage_pairings()

      true ->
        clear_persisted_pairings(data_path)
    end
  catch
    kind, reason -> {:error, {kind, reason}}
  end

  def clear_pairings(_data_path), do: {:ok, 0}

  defp clear_running_manager_pairings do
    pairings = HAP.AccessoryServerManager.controller_pairings()

    pairings
    |> Map.keys()
    |> Enum.each(&HAP.AccessoryServerManager.remove_controller_pairing/1)

    reload_discovery()
    {:ok, map_size(pairings)}
  end

  defp clear_running_storage_pairings do
    pairings = HAP.PersistentStorage.get(:pairings, %{})
    :ok = HAP.PersistentStorage.put(:pairings, %{})
    reload_discovery()
    {:ok, map_size(pairings)}
  end

  defp persisted_pairings?(data_path) do
    case CubDB.start_link(data_path) do
      {:ok, pid} ->
        pairings = CubDB.get(pid, :pairings, %{})
        CubDB.stop(pid)
        pairings != %{}

      _ ->
        false
    end
  end

  defp clear_persisted_pairings(data_path) do
    case CubDB.start_link(data_path) do
      {:ok, pid} ->
        pairings = CubDB.get(pid, :pairings, %{})
        result = CubDB.put(pid, :pairings, %{})
        CubDB.stop(pid)

        case result do
          :ok -> {:ok, map_size(pairings)}
          other -> {:error, other}
        end

      {:error, {:already_started, _pid}} ->
        {:error, :homekit_storage_in_use}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp reload_discovery do
    HAP.Discovery.reload()
  catch
    :exit, _reason -> :ok
  end
end
