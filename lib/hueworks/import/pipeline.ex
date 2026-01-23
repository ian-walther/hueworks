defmodule Hueworks.Import.Pipeline do
  @moduledoc false

  alias Hueworks.Repo
  alias Hueworks.Schemas.Bridge
  alias Hueworks.Schemas.BridgeImport
  alias Hueworks.Import.{Normalize, Plan}

  def create_import(%Bridge{} = bridge) do
    with {:ok, raw_blob} <- fetch_raw(bridge) do
      normalized_blob = Normalize.normalize(bridge, raw_blob)

      Repo.transaction(fn ->
        plan = Plan.build_default(normalized_blob)

        {:ok, bridge_import} =
          %BridgeImport{}
          |> BridgeImport.changeset(%{
            bridge_id: bridge.id,
            raw_blob: raw_blob,
            normalized_blob: normalized_blob,
            review_blob: plan,
            status: :normalized,
            imported_at: DateTime.utc_now() |> DateTime.truncate(:second)
          })
          |> Repo.insert()

        bridge_import
      end)
      |> case do
        {:ok, result} -> {:ok, result}
        {:error, reason} -> {:error, reason}
      end
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
    Hueworks.Import.Fetch.Hue.fetch_for_bridge(bridge)
  end

  defp do_fetch_raw(%Bridge{type: :caseta} = bridge) do
    Hueworks.Import.Fetch.Caseta.fetch_for_bridge(bridge)
  end

  defp do_fetch_raw(%Bridge{type: :ha} = bridge) do
    Hueworks.Import.Fetch.HomeAssistant.fetch_for_bridge(bridge)
  end
end
