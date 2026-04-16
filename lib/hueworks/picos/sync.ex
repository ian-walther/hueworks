defmodule Hueworks.Picos.Sync do
  @moduledoc false

  alias Hueworks.Import.Fetch.Caseta
  alias Hueworks.Picos.Devices
  alias Hueworks.Picos.Sync.Persistence
  alias Hueworks.Picos.Sync.Snapshot
  alias Hueworks.Repo
  alias Hueworks.Schemas.Bridge

  def sync_bridge_picos(%Bridge{type: :caseta} = bridge) do
    bridge
    |> caseta_fetch_module().fetch_for_bridge()
    |> then(&sync_bridge_picos(bridge, &1))
  rescue
    error -> {:error, Exception.message(error)}
  end

  def sync_bridge_picos(%Bridge{} = bridge, raw) when is_map(raw) do
    room_by_area_id =
      bridge.id
      |> Snapshot.room_ids_by_area_id(Snapshot.lights(raw))

    grouped_buttons =
      raw
      |> Snapshot.pico_buttons()
      |> Snapshot.group_buttons_by_device()

    Repo.transaction(fn ->
      Persistence.sync_devices(bridge, grouped_buttons, room_by_area_id)
    end)

    {:ok, Devices.list_for_bridge(bridge.id)}
  end

  defp caseta_fetch_module do
    Application.get_env(:hueworks, :caseta_pico_fetcher, Caseta)
  end
end
