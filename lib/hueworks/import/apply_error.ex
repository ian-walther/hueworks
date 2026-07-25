defmodule Hueworks.Import.ApplyError do
  @moduledoc false

  @detail_limit 180

  def message({:duplicate_classification_changed, type, source_id}) do
    "Duplicate classification changed for #{reference(type, source_id)}. Refresh the review and check the choices again."
  end

  def message({:invalid_duplicate, type, source_id}) do
    "The duplicate choice for #{reference(type, source_id)} is no longer valid. Refresh the review and choose again."
  end

  def message({:stale_resolution, type, source_id}) do
    "The review is out of date for #{reference(type, source_id)}. Refresh it and check the choices again."
  end

  def message(reason) do
    detail =
      reason
      |> inspect()
      |> String.replace(~r/\s+/, " ")
      |> String.slice(0, @detail_limit)

    "Import could not be applied. Review the selections and retry. Details: #{detail}"
  end

  defp reference(type, source_id), do: "#{type} #{source_id}"
end
