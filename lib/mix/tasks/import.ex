defmodule Mix.Tasks.Import do
  use Mix.Task

  @shortdoc "Import Hue/Caseta/Home Assistant exports into the database"

  @moduledoc """
  Import device exports into the database.

  Usage:

      mix import
      mix import hue
      mix import caseta
      mix import ha
      mix import home_assistant
  """

  alias Hueworks.Import

  @impl true
  def run(args) do
    Mix.Task.run("app.start")

    case normalize_args(args) do
      :all ->
        Import.import_from_files(%{
          hue: latest_export!("hue_devices_"),
          caseta: latest_export!("lutron_devices_"),
          ha: latest_export!("ha_entities_")
        })

      :hue ->
        Import.import_hue_file(latest_export!("hue_devices_"))

      :caseta ->
        Import.import_caseta_file(latest_export!("lutron_devices_"))

      :ha ->
        Import.import_home_assistant_file(latest_export!("ha_entities_"))

      :unknown ->
        Mix.raise("Unknown import target. Use: hue, caseta, ha, home_assistant")
    end
  end

  defp normalize_args([]), do: :all
  defp normalize_args(["hue"]), do: :hue
  defp normalize_args(["caseta"]), do: :caseta
  defp normalize_args(["ha"]), do: :ha
  defp normalize_args(["home_assistant"]), do: :ha
  defp normalize_args(_), do: :unknown

  defp latest_export!(prefix) do
    exports_dir = "exports"

    file =
      exports_dir
      |> File.ls!()
      |> Enum.filter(&String.starts_with?(&1, prefix))
      |> Enum.map(fn name ->
        path = Path.join(exports_dir, name)
        {path, File.stat!(path).mtime}
      end)
      |> Enum.sort_by(fn {_path, mtime} -> mtime end, :desc)
      |> List.first()

    case file do
      {path, _mtime} ->
        path

      nil ->
        Mix.raise("No export files found with prefix #{prefix} in #{exports_dir}/")
    end
  end
end
