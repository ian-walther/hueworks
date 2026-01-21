defmodule Hueworks.ImportPipeline do
  @moduledoc false

  alias Hueworks.Repo
  alias Hueworks.Schemas.Bridge
  alias Hueworks.Schemas.BridgeImport
  alias Hueworks.Import.Normalize

  def create_import(%Bridge{} = bridge) do
    with {:ok, raw_blob} <- fetch_raw(bridge) do
      normalized_blob = Normalize.normalize(bridge, raw_blob)

      changeset =
        BridgeImport.changeset(%BridgeImport{}, %{
          bridge_id: bridge.id,
          raw_blob: raw_blob,
          normalized_blob: normalized_blob,
          status: :normalized,
          imported_at: DateTime.utc_now() |> DateTime.truncate(:second)
        })

      Repo.insert(changeset)
    end
  rescue
    error -> {:error, Exception.message(error)}
  end

  def fetch_raw(%Bridge{} = bridge) do
    {:ok, do_fetch_raw(bridge)}
  rescue
    error -> {:error, Exception.message(error)}
  end

  defp do_fetch_raw(%Bridge{type: :hue} = bridge) do
    Hueworks.Fetch.Hue.fetch_for_bridge(bridge)
  end

  defp do_fetch_raw(%Bridge{type: :caseta} = bridge) do
    Hueworks.Fetch.Caseta.fetch_for_bridge(bridge)
  end

  defp do_fetch_raw(%Bridge{type: :ha} = bridge) do
    Hueworks.Fetch.HomeAssistant.fetch_for_bridge(bridge)
  end
end
