defmodule Hueworks.Import do
  @moduledoc """
  Import review orchestration.
  """

  alias Hueworks.Bridges
  alias Hueworks.Import.Materialize
  alias Hueworks.Repo
  alias Hueworks.Schemas.{Bridge, BridgeImport}

  def apply_review(%Bridge{} = bridge, %BridgeImport{} = bridge_import, normalized, plan) do
    result =
      Repo.transaction(fn ->
        with {:ok, reviewed} <- update_review_blob(bridge_import, plan),
             :ok <- Materialize.materialize(bridge, normalized, plan),
             {:ok, applied} <- mark_applied(reviewed),
             {:ok, updated_bridge} <- mark_bridge_complete(bridge) do
          %{bridge_import: applied, bridge: updated_bridge}
        else
          {:error, reason} -> Repo.rollback(reason)
        end
      end)

    case result do
      {:ok, %{bridge_import: applied} = applied_review} ->
        Bridges.prune_imports_for_bridge(applied.bridge_id)
        {:ok, applied_review}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp update_review_blob(bridge_import, plan) do
    bridge_import
    |> BridgeImport.changeset(%{review_blob: plan, status: :reviewed})
    |> Repo.update(stale_error_field: :review_blob)
  end

  defp mark_applied(bridge_import) do
    bridge_import
    |> BridgeImport.changeset(%{status: :applied})
    |> Repo.update(stale_error_field: :status)
  end

  defp mark_bridge_complete(bridge) do
    bridge
    |> Bridge.changeset(%{import_complete: true})
    |> Repo.update(stale_error_field: :import_complete)
  end
end
