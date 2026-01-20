defmodule Mix.Tasks.Sync do
  use Mix.Task

  @shortdoc "Fetch and import Hue/Caseta/Home Assistant data"

  @moduledoc """
  Fetch device data and import it without writing files.

  Usage:

      mix sync
      mix sync hue
      mix sync caseta
      mix sync ha
      mix sync home_assistant
  """

  alias Hueworks.Fetch
  alias Hueworks.Import
  alias Hueworks.Import.SaveState
  alias Hueworks.Bridges.Seed

  @impl true
  def run(args) do
    Mix.Task.run("app.start")
    Seed.seed!()

    case normalize_args(args) do
      :all ->
        %{
          hue: Import.import_hue_data(Fetch.Hue.fetch()),
          caseta: Import.import_caseta_data(Fetch.Caseta.fetch()),
          ha: Import.import_home_assistant_data(Fetch.HomeAssistant.fetch())
        }
        |> apply_disabled_list()

      :hue ->
        Import.import_hue_data(Fetch.Hue.fetch())
        |> apply_disabled_list()

      :caseta ->
        Import.import_caseta_data(Fetch.Caseta.fetch())
        |> apply_disabled_list()

      :ha ->
        Import.import_home_assistant_data(Fetch.HomeAssistant.fetch())
        |> apply_disabled_list()

      :unknown ->
        Mix.raise("Unknown sync target. Use: hue, caseta, ha, home_assistant")
    end
  end

  defp normalize_args([]), do: :all
  defp normalize_args(["hue"]), do: :hue
  defp normalize_args(["caseta"]), do: :caseta
  defp normalize_args(["ha"]), do: :ha
  defp normalize_args(["home_assistant"]), do: :ha
  defp normalize_args(_), do: :unknown

  defp apply_disabled_list(result) do
    SaveState.default_path()
    |> SaveState.load()
    |> SaveState.apply()

    result
  end
end
